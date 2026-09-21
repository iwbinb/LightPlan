import Foundation

/// Self-contained baseline, NOT a claim of instrument-grade astronomical precision.
/// Solar: standard Meeus/NOAA solar coordinates. Lunar: Schlyter elements + 19 perturbations,
/// with observer parallax in a WGS84 ellipsoid. Sources and measured QA limits are in docs/05.
/// No ephemeris library is linked; Swiss Ephemeris is an optional external QA oracle only.
public enum Astronomy {
    static let r = Double.pi / 180
    public static func normalize(_ value: Double) -> Double { let n = value.truncatingRemainder(dividingBy: 360); return n < 0 ? n + 360 : n }
    static func sind(_ a: Double) -> Double { sin(a*r) }
    static func cosd(_ a: Double) -> Double { cos(a*r) }
    static func atan2d(_ y: Double, _ x: Double) -> Double { atan2(y, x)/r }
    static func jd(_ d: Date) -> Double { d.timeIntervalSince1970/86400 + 2440587.5 }
    static func clamp(_ x: Double) -> Double { min(1,max(-1,x)) }
    struct Equatorial { var ra: Double; var dec: Double; var distanceEarthRadii: Double; var longitude: Double; var latitude: Double }
    static func solar(_ date: Date) -> Equatorial {
        let t=(jd(date)-2451545)/36525
        let l=normalize(280.46646+t*(36000.76983+t*0.0003032))
        let m=normalize(357.52911+t*(35999.05029-0.0001537*t))
        let e=0.016708634-t*(0.000042037+0.0000001267*t)
        let c=sind(m)*(1.914602-t*(0.004817+0.000014*t))+sind(2*m)*(0.019993-0.000101*t)+sind(3*m)*0.000289
        let trueLon=l+c, trueAnomaly=m+c
        let omega=125.04-1934.136*t
        let lambda=trueLon-0.00569-0.00478*sind(omega)
        let epsilon=23+(26+(21.448-t*(46.815+t*(0.00059-t*0.001813)))/60)/60+0.00256*cosd(omega)
        let ra=normalize(atan2d(cosd(epsilon)*sind(lambda),cosd(lambda)))
        let dec=asin(clamp(sind(epsilon)*sind(lambda)))/r
        let distanceAU=(1.000001018*(1-e*e))/(1+e*cosd(trueAnomaly))
        return Equatorial(ra:ra,dec:dec,distanceEarthRadii:distanceAU*149597870.7/6378.137,longitude:normalize(lambda),latitude:0)
    }
    static func lunar(_ date: Date) -> Equatorial {
        let d=jd(date)-2451543.5
        let node=normalize(125.1228-0.0529538083*d), i=5.1454
        let w=normalize(318.0634+0.1643573223*d), m=normalize(115.3654+13.0649929509*d), e=0.0549
        var eccentric=m*r
        for _ in 0..<10 { let delta=(eccentric-e*sin(eccentric)-m*r)/(1-e*cos(eccentric)); eccentric-=delta; if abs(delta)<1e-12 { break } }
        let x=60.2666*(cos(eccentric)-e), y=60.2666*sqrt(1-e*e)*sin(eccentric)
        var distance=hypot(x,y)
        let v=atan2d(y,x)
        let xe=distance*(cosd(node)*cosd(v+w)-sind(node)*sind(v+w)*cosd(i))
        let ye=distance*(sind(node)*cosd(v+w)+cosd(node)*sind(v+w)*cosd(i))
        let ze=distance*sind(v+w)*sind(i)
        var lon=atan2d(ye,xe), lat=atan2d(ze,hypot(xe,ye))
        let ms=normalize(356.0470+0.9856002585*d), ws=282.9404+4.70935e-5*d
        let lm=node+w+m, ls=ws+ms, elong=lm-ls, f=lm-node
        let longTerms:[(Double,Double)] = [(-1.274,m-2*elong),(0.658,2*elong),(-0.186,ms),(-0.059,2*m-2*elong),(-0.057,m-2*elong+ms),(0.053,m+2*elong),(0.046,2*elong-ms),(0.041,m-ms),(-0.035,elong),(-0.031,m+ms),(-0.015,2*f-2*elong),(0.011,m-4*elong)]
        for (amplitude,angle) in longTerms { lon += amplitude*sind(angle) }
        let latTerms:[(Double,Double)] = [(-0.173,f-2*elong),(-0.055,m-f-2*elong),(-0.046,m+f-2*elong),(0.033,f+2*elong),(0.017,2*m+f)]
        for (amplitude,angle) in latTerms { lat += amplitude*sind(angle) }
        distance += -0.58*cosd(m-2*elong)-0.46*cosd(2*elong)
        let eps=23.4393-3.563e-7*d
        let ex=cosd(lon)*cosd(lat), ey=sind(lon)*cosd(lat), ez=sind(lat)
        let qy=ey*cosd(eps)-ez*sind(eps), qz=ey*sind(eps)+ez*cosd(eps)
        return Equatorial(ra:normalize(atan2d(qy,ex)),dec:atan2d(qz,hypot(ex,qy)),distanceEarthRadii:distance,longitude:normalize(lon),latitude:lat)
    }
    /// Angular semidiameter from geocentric distance; used only for standard-horizon rise/set.
    /// Refraction is a standard atmosphere convention, not a weather measurement.
    public static func horizonThreshold(_ body: CelestialBody, at date: Date) -> Double {
        let eq = body == .sun ? solar(date) : lunar(date)
        let radiusEarthRadii = body == .sun ? 695700.0 / 6378.137 : 1737.4 / 6378.137
        let semidiameter = asin(clamp(radiusEarthRadii / eq.distanceEarthRadii)) / r
        return -(34.0 / 60.0 + semidiameter)
    }
    public static func position(_ body: CelestialBody, at date: Date, coordinate: Coordinate) throws -> SkyPosition {
        guard date.timeIntervalSince1970.isFinite else { throw LightPlanError.invalidDate }
        let julian=jd(date)
        guard julian >= 2415018.5, julian < 2488436.5 else { throw LightPlanError.invalidDate } // Guard band for local civil days at UTC offset/date-range boundaries.
        let eq = body == .sun ? solar(date) : lunar(date)
        let t=(julian-2451545)/36525
        let theta=normalize(280.46061837+360.98564736629*(julian-2451545)+0.000387933*t*t-t*t*t/38710000+coordinate.longitude)
        // Subtract observer vector instead of a singular topocentric RA approximation.
        let phi=coordinate.latitude*r, u=atan(0.99664719*tan(phi))
        let rhoCos=cos(u), rhoSin=0.99664719*sin(u)
        let ex=eq.distanceEarthRadii*cosd(eq.dec)*cosd(eq.ra)-rhoCos*cosd(theta)
        let ey=eq.distanceEarthRadii*cosd(eq.dec)*sind(eq.ra)-rhoCos*sind(theta)
        let ez=eq.distanceEarthRadii*sind(eq.dec)-rhoSin
        let ra=atan2d(ey,ex), dec=atan2d(ez,hypot(ex,ey)), h=(theta-ra)*r
        let east = -cosd(dec)*sin(h)
        let north = sind(dec)*cos(phi)-cosd(dec)*cos(h)*sin(phi)
        let up = sind(dec)*sin(phi)+cosd(dec)*cos(h)*cos(phi)
        let altitude=atan2d(up,hypot(east,north))
        let azimuth=normalize(atan2d(east,north))
        // Bennett standard-atmosphere model is illustrative; never use it as a weather guarantee.
        let correction = altitude > -1 && altitude < 89.9 ? (1.02/tan((altitude+10.3/(altitude+5.11))*r))/60 : 0
        return SkyPosition(azimuth:azimuth,altitude:altitude,apparentAltitude:altitude+max(0,correction))
    }
    public static func moonIllumination(at date: Date) -> Double {
        let moon=lunar(date), sun=solar(date)
        let cosElong=cosd(moon.latitude)*cosd(moon.longitude-sun.longitude)
        return min(1,max(0,(1-cosElong)/2))
    }
    public static func moonPhaseDegrees(at date: Date) -> Double { normalize(lunar(date).longitude-solar(date).longitude) }
    public static func lightBand(altitude: Double) -> LightBand {
        if altitude < -18 { return .night }; if altitude < -12 { return .astronomical }
        if altitude < -6 { return .nautical }; if altitude < -4 { return .blue }
        if altitude <= 6 { return .golden }; return .daylight
    }
    public static func angularSeparation(_ a: SkyPosition, _ b: SkyPosition) -> Double {
        acos(clamp(sind(a.altitude)*sind(b.altitude)+cosd(a.altitude)*cosd(b.altitude)*cosd(a.azimuth-b.azimuth)))/r
    }
}
