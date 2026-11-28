import AVFoundation
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Healthy HTTP cache limits tuned for iPad Air 2 (2 GB RAM): keeps assets cached on disk without RAM bloat
        URLCache.shared = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 96 * 1024 * 1024,
            diskPath: "nova_url_cache"
        )

        // Configure and activate audio session for web video & Picture-in-Picture across apps
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Keep launch resilient if audio session configuration fails in simulator/restricted states
        }
        return true
    }
}
