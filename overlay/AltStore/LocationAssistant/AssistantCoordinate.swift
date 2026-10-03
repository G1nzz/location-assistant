// LocationAssistant — AGPL-3.0-or-later. Coordinates supplied to idevice are WGS-84.
import Foundation
import CoreLocation

enum AssistantCoordinate {
    static func valid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite &&
        (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude)
    }

    static func parse(latitude: String, longitude: String) -> CLLocationCoordinate2D? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return valid(coordinate) ? coordinate : nil
    }

    // Mainland Apple Maps presents GCJ-02. Explicit coordinate entry is always WGS-84.
    static func mapToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard inChina(coordinate) else { return coordinate }
        var estimate = coordinate
        for _ in 0..<6 {
            let projected = wgs84ToMap(estimate)
            estimate.latitude -= projected.latitude - coordinate.latitude
            estimate.longitude -= projected.longitude - coordinate.longitude
        }
        return estimate
    }

    static func wgs84ToMap(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard inChina(coordinate) else { return coordinate }
        let x = coordinate.longitude - 105, y = coordinate.latitude - 35
        var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        lat += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lat += (20*sin(y * .pi) + 40*sin(y/3 * .pi))*2/3
        lat += (160*sin(y/12 * .pi) + 320*sin(y/30 * .pi))*2/3
        var lon = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        lon += (20*sin(6*x * .pi) + 20*sin(2*x * .pi))*2/3
        lon += (20*sin(x * .pi) + 40*sin(x/3 * .pi))*2/3
        lon += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi))*2/3
        let radians = coordinate.latitude / 180 * .pi
        let magic = 1 - 0.00669342162296594323 * pow(sin(radians), 2)
        lat = lat * 180 / ((6378245 * (1 - 0.00669342162296594323)) / pow(magic, 1.5) * .pi)
        lon = lon * 180 / (6378245 / sqrt(magic) * cos(radians) * .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + lat, longitude: coordinate.longitude + lon)
    }

    private static func inChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (72.004...137.8347).contains(coordinate.longitude) && (0.8293...55.8271).contains(coordinate.latitude)
    }
}
