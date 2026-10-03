import Foundation
import CoreLocation

func close(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, tolerance: Double = 0.000001) {
    precondition(abs(a.latitude - b.latitude) < tolerance && abs(a.longitude - b.longitude) < tolerance)
}
precondition(AssistantCoordinate.parse(latitude: " 39.9087 ", longitude: "116.3975") != nil)
for input in ["nan", "inf", "91", "-91", "abc", ""] {
    precondition(AssistantCoordinate.parse(latitude: input, longitude: "0") == nil)
}
precondition(AssistantCoordinate.parse(latitude: "0", longitude: "181") == nil)
let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
close(AssistantCoordinate.wgs84ToMap(paris), paris)
let beijing = CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)
let map = AssistantCoordinate.wgs84ToMap(beijing)
// Independent known Beijing GCJ-02 reference, approximately sub-meter tolerance.
close(map, CLLocationCoordinate2D(latitude: 39.9102265, longitude: 116.4037136), tolerance: 0.00001)
close(AssistantCoordinate.mapToWGS84(map), beijing)
print("Coordinate validation and Beijing conversion tests passed")
