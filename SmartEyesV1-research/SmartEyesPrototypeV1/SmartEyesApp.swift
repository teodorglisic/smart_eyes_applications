import SwiftUI
import MWDATCore
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}



@main
struct SmartEyesApp: App {
    @StateObject private var wearableManager = WearableManager.shared
    
    init() {
        // Core initialization of the Wearables SDK.
        // It must run exactly once during application startup.
        do {
            try Wearables.configure()
            print("Wearables SDK initialized successfully on startup.")
        } catch {
            print("Error initializing Wearables SDK: \(error.localizedDescription)")
        }
    }
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handles the callback from the Meta AI Companion App during registration
                    print("Received App Callback URL: \(url.absoluteString)")
                    Task {
                        await wearableManager.handleCallbackURL(url)
                    }
                }
        }
    }
}
