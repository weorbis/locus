import Foundation
import CoreFoundation
#if canImport(LocusSQLCipher)
import LocusSQLCipher
#endif

/// Arguments of the private `queryLocations` channel.
final class StoredLocationQuery {
    let limit: Int64?
    let offset: Int64
    let ascending: Bool
    let from: Int64?
    let to: Int64?
    private let minAccuracy: Double?
    private let maxAccuracy: Double?
    private let isMoving: Bool?
    private let bounds: (south: Double, west: Double, north: Double, east: Double)?
    private let timestampFallback: Int64
    private let localTimeZone = TimeZone.current

    static let microsPerSecond: Int64 = 1_000_000
    private static let secondsPerMinute: Int64 = 60
    private static let secondsPerHour = secondsPerMinute * 60
    private static let secondsPerDay = secondsPerHour * 24
    // Parse fractions separately: Date's floating-point representation cannot
    // preserve every epoch microsecond. Accept ordinary Dart ISO date/time forms.
    private static let timestampPattern = try! NSRegularExpression(pattern:
        #"^([+-]?[0-9]{4,6})-?([0-9]{2})-?([0-9]{2})(?:[Tt ]([0-9]{2})(?::?([0-9]{2}))?(?::?([0-9]{2}))?(?:[.,]([0-9]+))?(?: ?([Zz]|([+-])([0-9]{2})(?::?([0-9]{2}))?))?)?$"#)

    init(arguments: Any?) throws {
        guard let args = arguments as? [String: Any] else {
            throw Self.error("queryLocations requires a map")
        }
        from = try Self.integer(args["from"], name: "from")
        to = try Self.integer(args["to"], name: "to")
        limit = try Self.integer(args["limit"], name: "limit")
        offset = max(0, try Self.integer(args["offset"], name: "offset") ?? 0)
        guard let fallback = try Self.integer(args["timestampFallback"], name: "timestampFallback") else {
            throw Self.error("timestampFallback is required")
        }
        timestampFallback = fallback
        minAccuracy = try Self.number(args["minAccuracy"], name: "minAccuracy")
        maxAccuracy = try Self.number(args["maxAccuracy"], name: "maxAccuracy")
        isMoving = try Self.boolean(args["isMoving"], name: "isMoving")
        switch (args["sortOrder"] ?? "newestFirst") as? String {
        case "newestFirst": ascending = false
        case "oldestFirst": ascending = true
        default: throw Self.error("sortOrder must be newestFirst or oldestFirst")
        }
        if let value = args["bounds"], !(value is NSNull) {
            guard let map = value as? [String: Any],
                  let southwest = map["southwest"] as? [String: Any],
                  let northeast = map["northeast"] as? [String: Any],
                  let south = try Self.number(southwest["latitude"], name: "bounds.southwest.latitude"),
                  let west = try Self.number(southwest["longitude"], name: "bounds.southwest.longitude"),
                  let north = try Self.number(northeast["latitude"], name: "bounds.northeast.latitude"),
                  let east = try Self.number(northeast["longitude"], name: "bounds.northeast.longitude") else {
                throw Self.error("bounds requires southwest and northeast coordinates")
            }
            bounds = (south, west, north, east)
        } else {
            bounds = nil
        }
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "dev.locus.locationQuery", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func integer(_ value: Any?, name: String) throws -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              let integer = Int64(number.stringValue) else {
            throw error("\(name) must be a signed 64-bit integer")
        }
        return integer
    }

    private static func number(_ value: Any?, name: String) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw error("\(name) must be numeric")
        }
        return number.doubleValue
    }

    private static func boolean(_ value: Any?, name: String) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw error("\(name) must be boolean")
        }
        return number.boolValue
    }

    var filtersPayload: Bool {
        minAccuracy != nil || maxAccuracy != nil || isMoving != nil || bounds != nil
    }

    /// nil excludes the row; malformed rows are logged and skipped.
    func matchingTimestamp(_ value: OpaquePointer?) -> Int64? {
        guard let bytes = locus_sqlite3_value_text(value) else {
            NSLog("[locus.SQLiteStorage] queryLocations skipped a non-text payload")
            return nil
        }
        do {
            return try matchingTimestamp(payloadData: Data(bytes: bytes, count: Int(locus_sqlite3_value_bytes(value))))
        } catch {
            NSLog("[locus.SQLiteStorage] queryLocations skipped a malformed stored location: %@",
                  error.localizedDescription)
            return nil
        }
    }

    private func matchingTimestamp(payloadData data: Data) throws -> Int64? {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Self.error("Stored location payload is not an object")
        }
        let timestamp: Int64
        if let raw = payload["timestamp"], !(raw is NSNull) {
            guard let text = raw as? String else {
                throw Self.error("Stored location timestamp must be text")
            }
            timestamp = parseTimestamp(text) ?? timestampFallback
        } else {
            timestamp = timestampFallback
        }
        if let from, timestamp < from { return nil }
        if let to, timestamp > to { return nil }
        let coords = payload["coords"] as? [String: Any] ?? [:]
        var latitude = try Self.number(coords["latitude"], name: "stored latitude") ?? 0
        var longitude = try Self.number(coords["longitude"], name: "stored longitude") ?? 0
        let accuracy: Double
        if latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 {
            latitude = 0
            longitude = 0
            accuracy = -1
        } else {
            accuracy = try Self.number(coords["accuracy"], name: "stored accuracy") ?? 0
        }
        if let minAccuracy, accuracy > minAccuracy { return nil }
        if let maxAccuracy, accuracy < maxAccuracy { return nil }
        if let isMoving, try Self.boolean(payload["is_moving"], name: "stored is_moving") != isMoving {
            return nil
        }
        if let bounds,
           !(latitude >= bounds.south && latitude <= bounds.north &&
             longitude >= bounds.west && longitude <= bounds.east) { return nil }
        return timestamp
    }

    private func parseTimestamp(_ text: String) -> Int64? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.timestampPattern.firstMatch(in: text, range: range) else { return nil }
        func field(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        guard let rawYear = field(1).flatMap(Int.init),
              let rawMonth = field(2).flatMap(Int.init),
              let day = field(3).flatMap(Int.init) else { return nil }
        // DateTime.parse normalizes overflowing fields instead of rejecting
        // them. Normalize the month; civil-day/second arithmetic handles the rest.
        let monthsPerYear = 12
        let zeroBasedMonth = rawMonth - 1
        let year = rawYear + (zeroBasedMonth >= 0 ? zeroBasedMonth : zeroBasedMonth - 11) / monthsPerYear
        let month = ((zeroBasedMonth % monthsPerYear) + monthsPerYear) % monthsPerYear + 1
        let hour = field(4).flatMap(Int.init) ?? 0
        let minute = field(5).flatMap(Int.init) ?? 0
        let second = field(6).flatMap(Int.init) ?? 0
        let maximumEpochMicros: Int64 = 8_640_000_000_000_000_000
        let maximumEpochSeconds = maximumEpochMicros / Self.microsPerSecond
        let wallSeconds = Self.daysFromCivil(year: year, month: month, day: day) * Self.secondsPerDay +
            Int64(hour) * Self.secondsPerHour + Int64(minute) * Self.secondsPerMinute + Int64(second)
        let offset: Int64
        if field(8) == nil {
            offset = localTimeOffset(wallSeconds: wallSeconds, year: year)
        } else {
            let hours = field(10).flatMap(Int64.init) ?? 0
            let minutes = field(11).flatMap(Int64.init) ?? 0
            offset = (hours * Self.secondsPerHour + minutes * Self.secondsPerMinute) * (field(9) == "-" ? -1 : 1)
        }
        let seconds = wallSeconds - offset
        // Check before multiplication, then include fractions in the final
        // inclusive Dart DateTime range check (the maximum has no fraction).
        guard seconds >= -maximumEpochSeconds, seconds <= maximumEpochSeconds else { return nil }
        let fraction = String((field(7) ?? "").prefix(6))
        let micros = Int64(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0
        let timestamp = seconds * Self.microsPerSecond + micros
        guard timestamp >= -maximumEpochMicros, timestamp <= maximumEpochMicros else { return nil }
        return timestamp
    }

    /// Proleptic Gregorian days since 1970-01-01, using Howard Hinnant's
    /// days-from-civil formula. Shared by UTC and local timestamp parsing.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let adjustedYear = Int64(year - (month <= 2 ? 1 : 0))
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let marchBasedMonth = Int64(month + (month > 2 ? -3 : 9))
        let dayOfYear = (153 * marchBasedMonth + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let daysPerEra: Int64 = 146_097
        let unixEpochCivilDay: Int64 = 719_468
        return era * daysPerEra + dayOfEra - unixEpochCivilDay
    }

    /// Mirror Dart VM DateTime's equivalent-year and local-offset algorithms.
    /// Historical/future offsets use an equivalent modern year outside the
    /// signed-32-bit seconds range, rather than Foundation's historical rules.
    private func localTimeOffset(wallSeconds: Int64, year: Int) -> Int64 {
        let secondsPerDay = Self.secondsPerDay
        let twoHours = 2 * Self.secondsPerHour
        func zoneOffset(at seconds: Int64) -> Int64 {
            let maximumPlatformSeconds: Int64 = 0x7FFF_FFFF
            var equivalentSeconds = seconds
            if seconds < -maximumPlatformSeconds || seconds > maximumPlatformSeconds {
                // Offset probes are at most a few hours from the parsed wall
                // time, but may cross its year boundary.
                var probeYear = year
                while seconds < Self.daysFromCivil(year: probeYear, month: 1, day: 1) * secondsPerDay {
                    probeYear -= 1
                }
                while seconds >= Self.daysFromCivil(year: probeYear + 1, month: 1, day: 1) * secondsPerDay {
                    probeYear += 1
                }
                let originalDays = Self.daysFromCivil(year: probeYear, month: 1, day: 1)
                let weekday = ((originalDays + 4) % 7 + 7) % 7 // Sunday is zero.
                let leap = probeYear % 4 == 0 && (probeYear % 100 != 0 || probeYear % 400 == 0)
                let recentYear = (leap ? 1956 : 1967) + Int(weekday) * 12
                let cycleYears = 28
                let equivalentYear = 2008 + ((recentYear - 2008) % cycleYears + cycleYears) % cycleYears
                let equivalentDays = Self.daysFromCivil(year: equivalentYear, month: 1, day: 1)
                equivalentSeconds += (equivalentDays - originalDays) * secondsPerDay
            }
            return Int64(localTimeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(equivalentSeconds))))
        }
        var offset = zoneOffset(at: wallSeconds)
        if offset != 0 {
            let secondOffset = zoneOffset(at: wallSeconds - offset)
            if secondOffset != offset {
                let thirdOffset = zoneOffset(at: wallSeconds - secondOffset)
                // A forward DST gap uses the earlier zone (the later instant).
                return min(secondOffset, thirdOffset)
            }
            offset = secondOffset
        }
        let earlierOffset = zoneOffset(at: wallSeconds - offset - twoHours)
        if earlierOffset > offset {
            // An overlap uses the earliest valid instant, like Dart DateTime.
            if earlierOffset == offset + twoHours ||
                zoneOffset(at: wallSeconds - earlierOffset) == earlierOffset {
                return earlierOffset
            }
        }
        return offset
    }

}
