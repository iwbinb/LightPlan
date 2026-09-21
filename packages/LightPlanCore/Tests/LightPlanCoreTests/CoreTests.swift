import XCTest
@testable import LightPlanCore

final class CoreTests:XCTestCase {
    func date(_ value:String)->Date { ISO8601DateFormatter().date(from:value)! }
    func place(_ lat:Double=24.4478,_ lon:Double=118.0679,_ tz:String="Asia/Shanghai") throws -> Place {
        try Place(name:"Test",coordinate:Coordinate(latitude:lat,longitude:lon),timeZoneID:tz)
    }
    func testCoordinatesRejectOutOfRange() { XCTAssertThrowsError(try Coordinate(latitude:90.1,longitude:0));XCTAssertThrowsError(try Coordinate(latitude:0,longitude:181)) }
    func testCoordinatesRejectNonFinite() { XCTAssertThrowsError(try Coordinate(latitude:.nan,longitude:0));XCTAssertThrowsError(try Coordinate(latitude:0,longitude:.infinity)) }
    func testCoordinateDecodeValidates() { XCTAssertThrowsError(try JSONDecoder().decode(Coordinate.self,from:Data(#"{"latitude":100,"longitude":0}"#.utf8))) }
    func testCoordinateEndpoints() throws { _=try Coordinate(latitude:-90,longitude:-180);_=try Coordinate(latitude:90,longitude:180) }
    func testInvalidTimeZone() { XCTAssertThrowsError(try place(0,0,"Invalid/Place")) }
    func testPlaceNameValidation() throws { XCTAssertThrowsError(try Place(name:" ",coordinate:Coordinate(latitude:0,longitude:0),timeZoneID:"UTC")) }
    func testUTCNormalDay() throws { XCTAssertEqual(try LocalDay.interval(containing:date("2026-09-17T12:00:00Z"),timeZone:TimeZone(identifier:"UTC")!).duration,86400) }
    func testNewYorkSpringDST() throws { XCTAssertEqual(try LocalDay.interval(containing:date("2026-03-08T12:00:00Z"),timeZone:TimeZone(identifier:"America/New_York")!).duration,23*3600) }
    func testNewYorkAutumnDST() throws { XCTAssertEqual(try LocalDay.interval(containing:date("2026-11-01T12:00:00Z"),timeZone:TimeZone(identifier:"America/New_York")!).duration,25*3600) }
    func testBerlinSpringDST() throws { XCTAssertEqual(try LocalDay.interval(containing:date("2026-03-29T12:00:00Z"),timeZone:TimeZone(identifier:"Europe/Berlin")!).duration,23*3600) }
    func testLordHoweHalfHourDST() throws { XCTAssertEqual(try LocalDay.interval(containing:date("2026-10-04T12:00:00Z"),timeZone:TimeZone(identifier:"Australia/Lord_Howe")!).duration,23.5*3600) }
    func testKathmanduQuarterHourZone() throws { let day=try LocalDay.interval(containing:date("2026-09-17T12:00:00Z"),timeZone:TimeZone(identifier:"Asia/Kathmandu")!);XCTAssertEqual(day.start,date("2026-09-16T18:15:00Z")) }
    func testInvalidCalendarDate() { XCTAssertThrowsError(try LocalDay.date(year:2025,month:2,day:29,timeZone:.gmt)) }
    func testLeapDay() throws { XCTAssertEqual(try LocalDay.date(year:2024,month:2,day:29,timeZone:.gmt),date("2024-02-29T12:00:00Z")) }
    func testSkippedApiaDate() { XCTAssertThrowsError(try LocalDay.date(year:2011,month:12,day:30,timeZone:TimeZone(identifier:"Pacific/Apia")!)) }
    func testUnsupportedYear() { XCTAssertThrowsError(try LocalDay.date(year:1800,month:1,day:1,timeZone:.gmt)) }
    func testAngleNormalization() { XCTAssertEqual(Astronomy.normalize(-10),350);XCTAssertEqual(Astronomy.normalize(720),0);XCTAssertEqual(Astronomy.normalize(370),10) }
    func testSunIsFiniteAtPoles() throws { for lat in [-90.0,90.0]{let p=try Astronomy.position(.sun,at:date("2026-06-21T12:00:00Z"),coordinate:Coordinate(latitude:lat,longitude:0));XCTAssertTrue(p.altitude.isFinite && p.azimuth.isFinite)} }
    func testSolarDirectionSanity() throws { let c=try Coordinate(latitude:24.4478,longitude:118.0679);let morning=try Astronomy.position(.sun,at:date("2026-09-17T00:00:00Z"),coordinate:c);let evening=try Astronomy.position(.sun,at:date("2026-09-17T09:00:00Z"),coordinate:c);XCTAssertTrue((0...180).contains(morning.azimuth));XCTAssertTrue((180...360).contains(evening.azimuth)) }
    func testLunarIlluminationBounds() { for days in 0..<31 { let x=Astronomy.moonIllumination(at:date("2026-09-01T00:00:00Z").addingTimeInterval(Double(days)*86400));XCTAssertTrue((0...1).contains(x)) } }
    func testLunarPhaseNormalization() { XCTAssertTrue((0..<360).contains(Astronomy.moonPhaseDegrees(at:date("2026-09-17T12:00:00Z")))) }
    func testGoldenAndBlueDefinitions() { XCTAssertEqual(Astronomy.lightBand(altitude:-5),.blue);XCTAssertEqual(Astronomy.lightBand(altitude:0),.golden);XCTAssertEqual(Astronomy.lightBand(altitude:7),.daylight);XCTAssertEqual(Astronomy.lightBand(altitude:-19),.night) }
    func testGoldenHourCanContinueAfterSunset() throws {
        let summary=try DayEngine.calculate(place:place(),date:date("2026-09-17T12:00:00+08:00"))
        XCTAssertLessThan(try XCTUnwrap(summary.first(.sunset)?.date),try XCTUnwrap(summary.first(.goldenEveningEnd)?.date))
    }
    func testEventsAreSortedAndInsideLocalDay() throws {
        let s=try DayEngine.calculate(place:place(),date:date("2026-09-17T12:00:00+08:00"))
        XCTAssertEqual(s.events.map(\.date),s.events.map(\.date).sorted());for e in s.events{XCTAssertGreaterThanOrEqual(e.date,s.start);XCTAssertLessThan(e.date,s.end)}
    }
    func testRiseSetCrossingResiduals() throws {
        let p=try place();let s=try DayEngine.calculate(place:p,date:date("2026-09-17T12:00:00+08:00"))
        for k in [LightEventKind.sunrise,.sunset]{let e=try XCTUnwrap(s.first(k));let a=try Astronomy.position(.sun,at:e.date,coordinate:p.coordinate).altitude;XCTAssertEqual(a,-0.833,accuracy:0.003)}
    }
    func testWindowsPartitionEntireDay() throws {
        let s=try DayEngine.calculate(place:place(),date:date("2026-09-17T12:00:00+08:00"))
        XCTAssertEqual(s.windows.first?.start,s.start);XCTAssertEqual(s.windows.last?.end,s.end)
        XCTAssertEqual(s.windows.reduce(0){$0+$1.end.timeIntervalSince($1.start)},s.end.timeIntervalSince(s.start),accuracy:0.01)
        for (a,b) in zip(s.windows,s.windows.dropFirst()){XCTAssertEqual(a.end,b.start)}
    }
    func testPolarDay() throws {let s=try DayEngine.calculate(place:place(69.6492,18.9553,"Europe/Oslo"),date:date("2026-06-21T12:00:00Z"));XCTAssertNil(s.first(.sunrise));XCTAssertNil(s.first(.sunset));XCTAssertEqual(s.horizonState,"alwaysAbove")}
    func testPolarNightStillHasTwilight() throws {let s=try DayEngine.calculate(place:place(69.6492,18.9553,"Europe/Oslo"),date:date("2026-12-21T12:00:00Z"));XCTAssertNil(s.first(.sunrise));XCTAssertEqual(s.horizonState,"alwaysBelow");XCTAssertNotNil(s.first(.blueMorningStart))}
    func testSouthernHemisphereSummer() throws {let s=try DayEngine.calculate(place:place(-33.8688,151.2093,"Australia/Sydney"),date:date("2026-12-21T12:00:00+11:00"));XCTAssertGreaterThan(try XCTUnwrap(s.first(.sunset)?.date).timeIntervalSince(try XCTUnwrap(s.first(.sunrise)?.date)),13*3600)}
    func testDatelineDestinationDay() throws {let s=try DayEngine.calculate(place:place(1.87,-157.43,"Pacific/Kiritimati"),date:date("2026-09-17T12:00:00+14:00"));XCTAssertEqual(s.start,date("2026-09-16T10:00:00Z"));XCTAssertNotNil(s.first(.sunrise))}
    func testDSTEventsRetainActualDayLength() throws {let s=try DayEngine.calculate(place:place(40.7128,-74.006,"America/New_York"),date:date("2026-03-08T12:00:00Z"));XCTAssertEqual(s.end.timeIntervalSince(s.start),23*3600)}
    func testPlanArrival() throws {let p=try place();let d=date("2026-09-17T12:00:00+08:00");let s=try DayEngine.calculate(place:p,date:d);let plan=try ShootPlan(title:"Sunset",place:p,date:d,target:.sunset,arrivalLeadMinutes:40);let m=try Planner.milestones(plan:plan,summary:s);let a=try XCTUnwrap(m.first{$0.key=="plan.arrival"});XCTAssertEqual(s.first(.sunset)!.date.timeIntervalSince(a.date),2400,accuracy:0.01)}
    func testPlanNoEventDoesNotInventTime() throws {let p=try place(69.6492,18.9553,"Europe/Oslo");let d=date("2026-06-21T12:00:00Z");let s=try DayEngine.calculate(place:p,date:d);let plan=try ShootPlan(title:"Sunset",place:p,date:d,target:.sunset);XCTAssertThrowsError(try Planner.milestones(plan:plan,summary:s))}
    func testPastReminderNotScheduled() throws {let p=try place();let d=date("2026-09-17T12:00:00+08:00");let plan=try ShootPlan(title:"Sunset",place:p,date:d,target:.sunset);let s=try DayEngine.calculate(place:p,date:d);XCTAssertNil(Planner.reminder(plan:plan,summary:s,now:date("2026-09-18T12:00:00Z")))}
    func testNotificationCanBePreviousDay() throws {let p=try place();let d=date("2026-09-17T12:00:00+08:00");let plan=try ShootPlan(title:"Sunrise",place:p,date:d,target:.sunrise,reminderLeadMinutes:1440);let s=try DayEngine.calculate(place:p,date:d);XCTAssertLessThan(try XCTUnwrap(Planner.reminder(plan:plan,summary:s,now:date("2026-09-15T00:00:00Z"))),s.start)}
    func testDisabledReminder() throws {let p=try place();let d=date("2026-09-17T12:00:00+08:00");let plan=try ShootPlan(title:"Sunset",place:p,date:d,target:.sunset,reminderLeadMinutes:nil);let s=try DayEngine.calculate(place:p,date:d);XCTAssertNil(Planner.reminder(plan:plan,summary:s,now:date("2026-09-15T00:00:00Z")))}
    func testInvalidPlanLead() throws {XCTAssertThrowsError(try ShootPlan(title:"Test",place:place(),date:Date(),target:.sunset,arrivalLeadMinutes:-1))}
    func testBearingNorthAndEast() throws {let a=try Coordinate(latitude:0,longitude:0);XCTAssertEqual(try XCTUnwrap(Geometry.bearing(from:a,to:Coordinate(latitude:1,longitude:0))),0,accuracy:0.001);XCTAssertEqual(try XCTUnwrap(Geometry.bearing(from:a,to:Coordinate(latitude:0,longitude:1))),90,accuracy:0.001)}
    func testCoincidentBearingUnavailable() throws {let c=try Coordinate(latitude:0,longitude:0);XCTAssertNil(Geometry.bearing(from:c,to:c))}
    func testBacklightNeedsCameraBearing() {let s=SkyPosition(azimuth:270,altitude:10,apparentAltitude:10);XCTAssertEqual(Geometry.relation(cameraBearing:270,sun:s),.back);XCTAssertEqual(Geometry.relation(cameraBearing:90,sun:s),.front);XCTAssertEqual(Geometry.relation(cameraBearing:nil,sun:s),.unavailable)}
    func testShadowFlatGround() {XCTAssertEqual(Geometry.shadowLength(objectHeight:2,altitude:45)!,2,accuracy:0.0001);XCTAssertNil(Geometry.shadowLength(objectHeight:2,altitude:-1));XCTAssertNil(Geometry.shadowLength(objectHeight:2,altitude:0.5))}
    func testFreeReadAndExportNeverPaywalled() {XCTAssertTrue(AccessPolicy.allows(.readExistingPlan,unlocked:false));XCTAssertTrue(AccessPolicy.allows(.export,unlocked:false));XCTAssertTrue(AccessPolicy.allows(.restore,unlocked:false))}
    func testPremiumGates() {XCTAssertFalse(AccessPolicy.allows(.savePlan,unlocked:false));XCTAssertTrue(AccessPolicy.allows(.savePlan,unlocked:true));XCTAssertFalse(AccessPolicy.allows(.otherDates,unlocked:false))}
    func testArchiveRoundTrip() throws {let p=try place();let plan=try ShootPlan(title:"日落・Sunset",place:p,date:date("2026-09-17T12:00:00Z"),target:.sunset);let a=Archive(places:[p],plans:[plan]);let b=try Archive.decode(a.encoded());XCTAssertEqual(b.places[0],p);XCTAssertEqual(b.plans[0].title,plan.title)}
    func testUnknownSchemaDoesNotResetData() {XCTAssertThrowsError(try Archive.decode(Data(#"{"schemaVersion":2,"places":[],"plans":[]}"#.utf8)))}
    func testCorruptArchiveRejected() {XCTAssertThrowsError(try Archive.decode(Data("not json".utf8)))}
    func testDuplicateArchiveIDsRejected() throws {let p=try place();XCTAssertThrowsError(try Archive.decode(Archive(places:[p,p],plans:[]).encoded()))}
    func testOversizeArchiveRejected() {XCTAssertThrowsError(try Archive.decode(Data(repeating:0,count:5_000_001)))}
    func testFrozenIndependentEphemerisFixtures() throws {
        struct Row:Decodable{let body:CelestialBody;let timestamp:Double;let latitude:Double;let longitude:Double;let expectedAzimuth:Double;let expectedAltitude:Double;let maxSeparation:Double}
        let url=Bundle.module.url(forResource:"positions",withExtension:"json",subdirectory:"Fixtures")!
        let rows=try JSONDecoder().decode([Row].self,from:Data(contentsOf:url))
        XCTAssertEqual(rows.count,396)
        for row in rows {
            let actual=try Astronomy.position(row.body,at:Date(timeIntervalSince1970:row.timestamp),coordinate:Coordinate(latitude:row.latitude,longitude:row.longitude))
            let expected=SkyPosition(azimuth:row.expectedAzimuth,altitude:row.expectedAltitude,apparentAltitude:row.expectedAltitude)
            XCTAssertLessThanOrEqual(Astronomy.angularSeparation(actual,expected),row.maxSeparation,"\(row.body) @ \(row.timestamp) (\(row.latitude),\(row.longitude))")
        }
    }
}
