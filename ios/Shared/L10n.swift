import Foundation

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
    static func number(_ value:Double,decimals:Int=0)->String {
        value.formatted(.number.locale(locale).precision(.fractionLength(decimals)))
    }
}

/// IDs come from the same build settings as entitlements. Do not hard-code a different suite in an extension.
enum AppConfiguration {
    static var productID: String {
        (Bundle.main.object(forInfoDictionaryKey: "LifetimeProductIdentifier") as? String).flatMap { $0.contains("$(") ? nil : $0 } ?? "com.arenovo.lightplan.lifetime"
    }
    static let supportEmail = "hello@arenovo.com"

    static var appGroupID:String? {
        guard let value=Bundle.main.object(forInfoDictionaryKey:"AppGroupIdentifier") as? String,
              value.hasPrefix("group."),!value.contains("$(") else { return nil }
        return value
    }
    static var sharedDefaults:UserDefaults? {appGroupID.flatMap{UserDefaults(suiteName:$0)}}
}
