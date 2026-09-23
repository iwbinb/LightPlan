import Foundation

public enum PlanTarget: String, CaseIterable, Codable, Sendable {
    case sunrise, sunset, goldenMorning, goldenEvening, blueEvening, composition
    public static var solarTargets: [Self] { allCases.filter { $0 != .composition } }
}
public struct PlanMilestone: Identifiable, Codable, Sendable {
    public var id: String { key + ":" + String(date.timeIntervalSince1970) }
    public let key: String
    public let date: Date
}
public struct ShootPlan: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var place: Place
    public var date: Date
    public var target: PlanTarget
    public var composition: CompositionPlan?
    /// Optional for compatibility with existing v1/v2 archives. Never uploaded automatically.
    public var notes: String?
    /// Optional additions keep existing v1/v2 archives readable.
    public var collectionName: String?
    public var completedAt: Date?
    public var arrivalLeadMinutes: Int
    public var reminderLeadMinutes: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public init(id:UUID=UUID(),title:String,place:Place,date:Date,target:PlanTarget,arrivalLeadMinutes:Int=30,reminderLeadMinutes:Int?=30,now:Date=Date(),composition:CompositionPlan?=nil,notes:String?=nil,collectionName:String?=nil,completedAt:Date?=nil) throws {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count<=100,(0...240).contains(arrivalLeadMinutes),
              reminderLeadMinutes == nil || (0...1440).contains(reminderLeadMinutes!) else { throw LightPlanError.invalidPlan }
        try LocalDay.validate(date, timeZone: place.timeZone)
        _ = try place.validated()
        guard (target == .composition) == (composition != nil) else { throw LightPlanError.invalidPlan }
        if let composition { _ = try composition.validated(observer: place, day: date) }
        guard now.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        guard (notes?.count ?? 0) <= 2000 else { throw LightPlanError.invalidPlan }
        guard (collectionName?.count ?? 0) <= 60 else { throw LightPlanError.invalidPlan }
        guard completedAt?.timeIntervalSince1970.isFinite != false else { throw LightPlanError.invalidDate }
        self.id=id; self.title=title; self.place=place; self.date=date; self.target=target; self.composition=composition; self.arrivalLeadMinutes=arrivalLeadMinutes
        self.reminderLeadMinutes=reminderLeadMinutes; self.createdAt=now; self.updatedAt=now
        self.notes=notes
        self.collectionName=collectionName; self.completedAt=completedAt
    }
    public func validated() throws -> ShootPlan {
        let _=try Self(id:id,title:title,place:place,date:date,target:target,arrivalLeadMinutes:arrivalLeadMinutes,reminderLeadMinutes:reminderLeadMinutes,now:createdAt,composition:composition,notes:notes,collectionName:collectionName,completedAt:completedAt)
        guard date.timeIntervalSince1970.isFinite,createdAt.timeIntervalSince1970.isFinite,updatedAt.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        return self
    }
}
public enum Planner {
    public static func anchorKind(_ target:PlanTarget)->LightEventKind? {
        switch target { case .sunrise:return .sunrise; case .sunset:return .sunset; case .goldenMorning:return .goldenMorningStart; case .goldenEvening:return .goldenEveningStart; case .blueEvening:return .goldenEveningEnd; case .composition:return nil }
    }
    public static func anchorDate(plan: ShootPlan, summary: DaySummary) -> Date? {
        guard (try? plan.validated()) != nil,
              summary.place.coordinate == plan.place.coordinate,
              summary.place.timeZoneID == plan.place.timeZoneID,
              LocalDay.same(plan.date, summary.start, timeZone: plan.place.timeZone) else { return nil }
        if let composition = plan.composition {
            return (summary.start..<summary.end).contains(composition.instant) ? composition.instant : nil
        }
        return anchorKind(plan.target).flatMap { summary.first($0)?.date }
    }
    public static func milestones(plan:ShootPlan,summary:DaySummary) throws -> [PlanMilestone] {
        guard summary.place.coordinate == plan.place.coordinate,
              summary.place.timeZoneID == plan.place.timeZoneID,
              LocalDay.same(plan.date, summary.start, timeZone: plan.place.timeZone) else { throw LightPlanError.invalidPlan }
        guard let anchor=anchorDate(plan: plan, summary: summary) else { throw LightPlanError.noEvent }
        let arrival=anchor.addingTimeInterval(-Double(plan.arrivalLeadMinutes)*60)
        if plan.target == .composition {
            return [PlanMilestone(key:"plan.arrival",date:arrival), PlanMilestone(key:"target.composition",date:anchor)]
        }
        var events=summary.events.filter { event in
            event.date >= arrival && event.date <= anchor.addingTimeInterval(3*3600) &&
            ![.moonrise,.moonset,.nauticalDawn,.nauticalDusk,.astronomicalDawn,.astronomicalDusk].contains(event.kind)
        }.map { PlanMilestone(key:$0.kind.key,date:$0.date) }
        events.append(PlanMilestone(key:"plan.arrival",date:arrival))
        return events.sorted { $0.date < $1.date }
    }
    public static func reminder(plan:ShootPlan,summary:DaySummary,now:Date)->Date? {
        guard plan.completedAt == nil,now.timeIntervalSince1970.isFinite,let lead=plan.reminderLeadMinutes,let anchor=anchorDate(plan: plan, summary: summary) else { return nil }
        let date=anchor.addingTimeInterval(-Double(lead)*60)
        return date>now ? date : nil
    }
}
public enum LightRelation: String, Sendable { case front, side, back, unavailable }
public enum Geometry {
    public static func bearing(from a:Coordinate,to b:Coordinate)->Double? {
        let r=Double.pi/180,d=(b.longitude-a.longitude)*r
        let y=sin(d)*cos(b.latitude*r)
        let x=cos(a.latitude*r)*sin(b.latitude*r)-sin(a.latitude*r)*cos(b.latitude*r)*cos(d)
        if hypot(x,y)<1e-12 { return nil }
        return Astronomy.normalize(atan2(y,x)/r)
    }
    public static func relation(cameraBearing:Double?,sun:SkyPosition)->LightRelation {
        guard let bearing=cameraBearing,bearing.isFinite,sun.altitude>0 else { return .unavailable }
        let delta=abs(Astronomy.normalize(sun.azimuth-bearing+180)-180)
        if delta<45 { return .back } // camera looks toward the sun: subject is backlit.
        if delta>135 { return .front }; return .side
    }
    public static func shadowLength(objectHeight:Double,altitude:Double)->Double? {
        guard objectHeight.isFinite,altitude.isFinite,objectHeight>0,altitude>=1,altitude<90 else { return nil }
        return objectHeight/tan(altitude*Double.pi/180) // Ideal level ground only.
    }
}
public struct Archive: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2
    public var schemaVersion:Int=Self.currentSchemaVersion
    public var places:[Place]
    public var plans:[ShootPlan]
    public init(places:[Place],plans:[ShootPlan]) { self.places=places;self.plans=plans }
    public func encoded() throws -> Data {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else { throw LightPlanError.unsupportedSchema }
        var output = self
        output.schemaVersion = Self.currentSchemaVersion
        try output.validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        guard data.count <= 5_000_000 else { throw LightPlanError.tooManyItems }
        return data
    }
    public func validate() throws {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else { throw LightPlanError.unsupportedSchema }
        guard schemaVersion >= 2 || !plans.contains(where: { $0.composition != nil || $0.target == .composition }) else { throw LightPlanError.unsupportedSchema }
        guard places.count <= 10000, plans.count <= 10000 else { throw LightPlanError.tooManyItems }
        guard Set(places.map(\.id)).count == places.count, Set(plans.map(\.id)).count == plans.count else { throw LightPlanError.corruptArchive }
        for place in places { _ = try place.validated() }
        for plan in plans { _ = try plan.validated() }
    }
    public static func decode(_ data:Data)throws->Archive {
        guard data.count<=5_000_000 else { throw LightPlanError.tooManyItems }
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let archive=try decoder.decode(Self.self,from:data)
        guard (1...Self.currentSchemaVersion).contains(archive.schemaVersion) else { throw LightPlanError.unsupportedSchema }
        guard archive.places.count<=10000,archive.plans.count<=10000 else { throw LightPlanError.tooManyItems }
        guard Set(archive.places.map(\.id)).count==archive.places.count,Set(archive.plans.map(\.id)).count==archive.plans.count else { throw LightPlanError.corruptArchive }
        try archive.validate()
        return archive
    }
}
