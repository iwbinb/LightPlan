import Foundation
import LightPlanCore

enum L10n {
    static var language: String { UserDefaults.standard.string(forKey: "language") ?? "system" }

    static let supported=["en","zh-Hans","zh-Hant","ja","ko","de","fr","th","pt-PT"]
    static let names=["English","简体中文","繁體中文","日本語","한국어","Deutsch","Français","ไทย","Português (Portugal)"]
    static func text(_ key:String,language:String?=nil)->String {
        let selected=language ?? UserDefaults.standard.string(forKey:"language") ?? "system"
        guard selected != "system",let path=Bundle.main.path(forResource:selected,ofType:"lproj"),let bundle=Bundle(path:path) else {
            return NSLocalizedString(key,comment:"")
        }
        return bundle.localizedString(forKey:key,value:nil,table:"Localizable")
    }
    static var locale:Locale {
        let selected=UserDefaults.standard.string(forKey:"language") ?? "system"
        return selected == "system" ? .autoupdatingCurrent : Locale(identifier:selected)
    }
    static func time(_ date:Date,zone:TimeZone,language:String?=nil)->String {
        let chosen=language.map { $0 == "system" ? Locale.autoupdatingCurrent : Locale(identifier:$0) } ?? locale
        let f=DateFormatter();f.locale=chosen;f.calendar=Calendar(identifier: .gregorian);f.timeZone=zone;f.dateStyle = .none;f.timeStyle = .short
        let clock = (Bundle.main.bundleURL.pathExtension == "appex" ? AppConfiguration.sharedDefaults?.string(forKey: "widgetClock") : UserDefaults.standard.string(forKey: "clockFormat")) ?? "system"
        if clock == "24h" { f.dateFormat = "HH:mm" }
        else if clock == "12h" { f.setLocalizedDateFormatFromTemplate("hmm a") }
        return f.string(from:date)
    }
    static func fullDate(_ date:Date,zone:TimeZone,language:String?=nil)->String {
        let f=DateFormatter();f.locale=language.map { $0 == "system" ? Locale.autoupdatingCurrent : Locale(identifier: $0) } ?? locale;f.calendar=Calendar(identifier: .gregorian);f.timeZone=zone;f.dateStyle = .medium;f.timeStyle = .none
        return f.string(from:date)
    }
    /// Disambiguate repeated local times during a daylight-saving fall-back.
    static func utcOffset(at date: Date, zone: TimeZone) -> String {
        let offset = zone.secondsFromGMT(for: date)
        guard offset != 0 else { return "UTC" }
        let seconds = abs(offset)
        var value = "UTC" + (offset < 0 ? "−" : "+")
            + String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
        if seconds % 60 != 0 { value += String(format: ":%02d", seconds % 60) }
        return value
    }
    static func number(_ value:Double,decimals:Int=0)->String {
        value.formatted(.number.locale(locale).precision(.fractionLength(decimals)))
    }
    static func focalLength(_ value: Double) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
    }
    static func coordinate(_ value: Coordinate) -> String {
        number(value.latitude, decimals: 6) + " · " + number(value.longitude, decimals: 6)
    }
    static func conditions(_ value: OpportunityConstraints) -> String {
        func range(_ range: ClosedRange<Double>) -> String {
            number(range.lowerBound, decimals: 1) + "°…" + number(range.upperBound, decimals: 1) + "°"
        }
        var parts = ["Δ ≤" + number(value.maximumErrorDegrees, decimals: 1) + "°",
                     text("composition.altitude") + " " + range(value.altitudeRange)]
        if let solar = value.solarAltitudeRange { parts.append(text("body.sun") + " " + range(solar)) }
        if let moon = value.moonIlluminationRange {
            parts.append(text("moon.illumination") + " " + number(moon.lowerBound * 100) + "–" + number(moon.upperBound * 100) + "%")
        }
        return text("opportunity.conditions") + ": " + parts.joined(separator: " · ")
    }
}

/// IDs come from the same build settings as entitlements. Do not hard-code a different suite in an extension.
enum AppConfiguration {
    static var supportURL: URL? { website("SupportURL") }
    static var privacyURL: URL? { website("PrivacyPolicyURL") }
    static var contactURL: URL? {
        guard let email = Bundle.main.object(forInfoDictionaryKey: "SupportEmail") as? String,
              email.contains("@"), !email.contains(where: { $0.isWhitespace }),
              !email.contains("$(") else { return nil }
        var components = URLComponents(); components.scheme = "mailto"; components.path = email
        return components.url
    }
    private static func website(_ key: String) -> URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static var appGroupID:String? {
        guard let value=Bundle.main.object(forInfoDictionaryKey:"AppGroupIdentifier") as? String,
              value.hasPrefix("group."),!value.contains("$(") else { return nil }
        return value
    }
    static var sharedDefaults:UserDefaults? {appGroupID.flatMap{UserDefaults(suiteName:$0)}}
}
