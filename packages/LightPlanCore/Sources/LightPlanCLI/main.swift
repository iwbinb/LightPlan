import Foundation
import LightPlanCore

@main struct CLI {
    static func main() {
        do {
            let args=Array(CommandLine.arguments.dropFirst())
            let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601;encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            let output:Data
            if args.first == "positions" {
                struct Input:Decodable { let body:CelestialBody;let timestamp:Double;let latitude:Double;let longitude:Double }
                let data=FileHandle.standardInput.readDataToEndOfFile()
                let rows=try JSONDecoder().decode([Input].self,from:data)
                let result=try rows.map { try Astronomy.position($0.body,at:Date(timeIntervalSince1970:$0.timestamp),coordinate:Coordinate(latitude:$0.latitude,longitude:$0.longitude)) }
                output=try encoder.encode(result)
            } else {
                let lat=args.count>0 ? Double(args[0]) : 24.4478
                let lon=args.count>1 ? Double(args[1]) : 118.0679
                guard let lat,let lon else { throw LightPlanError.invalidCoordinate }
                let tz=args.count>2 ? args[2] : "Asia/Shanghai"
                let iso=args.count>3 ? args[3] : "2026-09-17T12:00:00+08:00"
                guard let date=ISO8601DateFormatter().date(from:iso) else { throw LightPlanError.invalidDate }
                let p=try Place(name:"CLI input",coordinate:Coordinate(latitude:lat,longitude:lon),timeZoneID:tz)
                output=try encoder.encode(DayEngine.calculate(place:p,date:date))
            }
            FileHandle.standardOutput.write(output);FileHandle.standardOutput.write(Data([10]))
        } catch {
            FileHandle.standardError.write(Data("LightPlan: \(error)\n".utf8));exit(1)
        }
    }
}
