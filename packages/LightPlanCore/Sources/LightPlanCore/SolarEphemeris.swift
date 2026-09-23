import Foundation

/// VSOP87D Earth -> apparent geocentric Sun, of-date FK5 coordinates.
/// Solar/nutation transformations and tables adapted from astronomia (MIT), pinned in
/// scripts/generate_solar_coefficients.py. Full notice: licenses/astronomia-MIT.txt.
/// Unlike the former low-order solar orbit, this retains planetary perturbations.
/// Independent event/position evidence and remaining limits are in astronomy-events reports.
enum SolarEphemeris {
    struct Term: Sendable {
        let amplitude: Double
        let phase: Double
        let frequency: Double
        init(_ amplitude: Double, _ phase: Double, _ frequency: Double) {
            self.amplitude = amplitude; self.phase = phase; self.frequency = frequency
        }
    }
    private static let radians = Double.pi / 180

    private static func series(_ terms: [[Term]], _ tau: Double) -> Double {
        var value = 0.0
        for row in terms.reversed() {
            var coefficient = 0.0
            for term in row.reversed() { coefficient += term.amplitude * cos(term.phase + term.frequency * tau) }
            value = value * tau + coefficient
        }
        return value
    }

    private static func centuriesTT(at date: Date) -> Double {
        let ut = Astronomy.jd(date)
        let year = 2000 + (ut - 2451545) / 365.2425
        return (ut + deltaTSeconds(year: year) / 86400 - 2451545) / 36525
    }

    static func distanceEarthRadii(at date: Date) -> Double {
        series(radiusTerms, centuriesTT(at: date) / 10) * 149597870.7 / 6378.137
    }

    static func position(at date: Date) -> Astronomy.Equatorial {
        let centuries = centuriesTT(at: date), tau = centuries / 10
        var longitude = series(longitudeTerms, tau) + .pi
        var latitude = -series(latitudeTerms, tau)
        let distanceAU = series(radiusTerms, tau)
        // VSOP dynamical ecliptic -> FK5, then aberration and full nutation.
        let correctedLongitude = longitude - (1.397 * centuries + 0.00031 * centuries * centuries) * radians
        longitude -= 0.09033 / 3600 * radians
        latitude += 0.03916 / 3600 * radians * (cos(correctedLongitude) - sin(correctedLongitude))
        let nutation = nutation(centuries)
        longitude += nutation.longitude - 20.4898 / (3600 * distanceAU) * radians
        let meanObliquity = (23 + (26 + (21.448 - 46.815 * centuries - 0.00059 * centuries * centuries
            + 0.001813 * centuries * centuries * centuries) / 60) / 60) * radians
        let obliquity = meanObliquity + nutation.obliquity
        let ra = atan2(cos(obliquity) * sin(longitude) - tan(latitude) * sin(obliquity), cos(longitude)) / radians
        let dec = asin(Astronomy.clamp(sin(latitude) * cos(obliquity) + cos(latitude) * sin(obliquity) * sin(longitude))) / radians
        return Astronomy.Equatorial(ra: Astronomy.normalize(ra), dec: dec,
            distanceEarthRadii: distanceAU * 149597870.7 / 6378.137,
            longitude: Astronomy.normalize(longitude / radians), latitude: latitude / radians,
            siderealCorrection: nutation.longitude * cos(obliquity) / radians)
    }

    private static func nutation(_ t: Double) -> (longitude: Double, obliquity: Double) {
        let t2 = t * t, t3 = t2 * t
        let arguments = [
            (297.85036 + 445267.11148 * t - 0.0019142 * t2 + t3 / 189474) * radians,
            (357.52772 + 35999.050340 * t - 0.0001603 * t2 - t3 / 300000) * radians,
            (134.96298 + 477198.867398 * t + 0.0086972 * t2 + t3 / 56250) * radians,
            (93.27191 + 483202.017538 * t - 0.0036825 * t2 + t3 / 327270) * radians,
            (125.04452 - 1934.136261 * t + 0.0020708 * t2 + t3 / 450000) * radians
        ]
        var longitude = 0.0, obliquity = 0.0
        for row in nutationTerms.reversed() {
            var angle = 0.0
            for index in 0..<5 { angle += row[index] * arguments[index] }
            longitude += (row[5] + row[6] * t) * sin(angle)
            obliquity += (row[7] + row[8] * t) * cos(angle)
        }
        let scale = 0.0001 / 3600 * radians
        return (longitude * scale, obliquity * scale)
    }

    /// Espenak/Meeus historical/predicted TT−UT polynomial, limited to the app's guard band.
    /// https://eclipse.gsfc.nasa.gov/SEcat5/deltatpoly.html
    /// Future Earth rotation is uncertain; this is a prediction, not measured future time.
    static func deltaTSeconds(year: Double) -> Double {
        func polynomial(_ t: Double, _ coefficients: [Double]) -> Double {
            coefficients.reversed().reduce(0) { $0 * t + $1 }
        }
        switch year {
        case ..<1900: return polynomial(year - 1860, [7.62, 0.5737, -0.251754, 0.01680668, -0.0004473624, 1.0 / 233174.0])
        case ..<1920: return polynomial(year - 1900, [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197])
        case ..<1941: return polynomial(year - 1920, [21.20, 0.84493, -0.076100, 0.0020936])
        case ..<1961: return polynomial(year - 1950, [29.07, 0.407, -1.0 / 233.0, 1.0 / 2547.0])
        case ..<1986: return polynomial(year - 1975, [45.45, 1.067, -1.0 / 260.0, -1.0 / 718.0])
        case ..<2005: return polynomial(year - 2000, [63.86, 0.3345, -0.060374, 0.0017275, 0.000651814, 0.00002373599])
        case ..<2050: return polynomial(year - 2000, [62.92, 0.32217, 0.005589])
        default:
            let u = (year - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - year)
        }
    }
}
