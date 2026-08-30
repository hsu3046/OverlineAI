import CoreLocation
import Observation

@MainActor
@Observable
final class CommunityLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var errorMessage: String?
    private(set) var isRequesting = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        errorMessage = nil
        switch authorizationStatus {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.requestLocation()
        case .denied:
            isRequesting = false
            errorMessage = "위치 권한을 허용하면 가까운 서점과 도서관을 볼 수 있습니다."
        case .restricted:
            isRequesting = false
            errorMessage = "이 iPhone에서는 위치를 사용할 수 없습니다."
        @unknown default:
            isRequesting = false
            errorMessage = "현재 위치를 확인할 수 없습니다."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isRequesting = true
            manager.requestLocation()
        } else if authorizationStatus != .notDetermined {
            isRequesting = false
            requestCurrentLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        isRequesting = false
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        errorMessage = "현재 위치를 확인하지 못했습니다. 다시 시도해 주세요."
    }
}
