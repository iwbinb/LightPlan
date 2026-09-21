import Foundation

public enum PlanTarget: String, CaseIterable, Codable, Sendable { case sunrise, sunset, goldenMorning, goldenEvening, blueEvening }
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
    public var arrivalLeadMinutes: Int
    public var reminderLeadMinutes: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public init(id:UUID=UUID(),title:String,place:Place,date:Date,target:PlanTarget,arrivalLeadMinutes:Int=30,reminderLeadMinutes:Int?=30,now:Date=Date()) throws {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count<=100,(0...240).contains(arrivalLeadMinutes),
              reminderLeadMinutes == nil || (0...1440).contains(reminderLeadMinutes!) else { throw LightPlanError.invalidPlan }
        try LocalDay.validate(date, timeZone: place.timeZone)
        _ = try place.validated()
        guard now.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        self.id=id; self.title=title; self.place=place; self.date=date; self.target=target; self.arrivalLeadMinutes=arrivalLeadMinutes
        self.reminderLeadMinutes=reminderLeadMinutes; self.createdAt=now; self.updatedAt=now
    }
    public func validated() throws -> ShootPlan {
        let _=try Self(id:id,title:title,place:place,date:date,target:target,arrivalLeadMinutes:arrivalLeadMinutes,reminderLeadMinutes:reminderLeadMinutes,now:createdAt)
        guard date.timeIntervalSince1970.isFinite,createdAt.timeIntervalSince1970.isFinite,updatedAt.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        return self
    }
}
public enum Planner {
    public static func anchorKind(_ target:PlanTarget)->LightEventKind {
        switch target { case .sunrise:return .sunrise; case .sunset:return .sunset; case .goldenMorning:return .goldenMorningStart; case .goldenEvening:return .goldenEveningStart; case .blueEvening:return .goldenEveningEnd }
    }
    public static func milestones(plan:ShootPlan,summary:DaySummary) throws -> [PlanMilestone] {
        guard summary.place.coordinate == plan.place.coordinate,
              summary.place.timeZoneID == plan.place.timeZoneID,
              LocalDay.same(plan.date, summary.start, timeZone: plan.place.timeZone) else { throw LightPlanError.invalidPlan }
        guard let anchor=summary.first(anchorKind(plan.target)) else { throw LightPlanError.noEvent }
        let arrival=anchor.date.addingTimeInterval(-Double(plan.arrivalLeadMinutes)*60)
        var events=summary.events.filter { event in
            event.date >= arrival && event.date <= anchor.date.addingTimeInterval(3*3600) &&
            ![.moonrise,.moonset,.nauticalDawn,.nauticalDusk,.astronomicalDawn,.astronomicalDusk].contains(event.kind)
        }.map { PlanMilestone(key:$0.kind.key,date:$0.date) }
        events.append(PlanMilestone(key:"plan.arrival",date:arrival))
        return events.sorted { $0.date < $1.date }
    }
    public static func reminder(plan:ShootPlan,summary:DaySummary,now:Date)->Date? {
        guard summary.place.coordinate == plan.place.coordinate, summary.place.timeZoneID == plan.place.timeZoneID, LocalDay.same(plan.date, summary.start, timeZone: plan.place.timeZone), let lead=plan.reminderLeadMinutes,let event=summary.first(anchorKind(plan.target)) else { return nil }
        let date=event.date.addingTimeInterval(-Double(lead)*60)
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
public enum Feature: String, Sendable { case today, todayMap, otherDates, otherPlaces, savePlan, favorites, widget, readExistingPlan, export, restore }
public enum AccessPolicy {
    public static func allows(_ feature:Feature,unlocked:Bool)->Bool {
        if unlocked { return true }
        return [.today,.todayMap,.readExistingPlan,.export,.restore].contains(feature)
    }
}
public struct Archive: Codable, Sendable, Equatable {
    public var schemaVersion:Int=1
    public var places:[Place]
    public var plans:[ShootPlan]
    public init(places:[Place],plans:[ShootPlan]) { self.places=places;self.plans=plans }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 5_000_000 else { throw LightPlanError.tooManyItems }
        return data
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw LightPlanError.unsupportedSchema }
        guard places.count <= 10000, plans.count <= 10000 else { throw LightPlanError.tooManyItems }
        guard Set(places.map(\.id)).count == places.count, Set(plans.map(\.id)).count == plans.count else { throw LightPlanError.corruptArchive }
        for place in places { _ = try place.validated() }
        for plan in plans { _ = try plan.validated() }
    }
    public static func decode(_ data:Data)throws->Archive {
        guard data.count<=5_000_000 else { throw LightPlanError.tooManyItems }
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        let archive=try decoder.decode(Self.self,from:data)
        guard archive.schemaVersion==1 else { throw LightPlanError.unsupportedSchema }
        guard archive.places.count<=10000,archive.plans.count<=10000 else { throw LightPlanError.tooManyItems }
        guard Set(archive.places.map(\.id)).count==archive.places.count,Set(archive.plans.map(\.id)).count==archive.plans.count else { throw LightPlanError.corruptArchive }
        try archive.validate()
        return archive
    }
}
