import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Reads GMSApiKey from Info.plist rather than hardcoding it here — the
    // only place that needs the real key pasted in is Info.plist, and it
    // stays flavor-swappable (each build configuration's own Info.plist can
    // carry a different value) without ever touching this file again.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsApiKey.isEmpty, mapsApiKey != "PASTE_REAL_IOS_GOOGLE_MAPS_KEY_HERE" {
      GMSServices.provideAPIKey(mapsApiKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
