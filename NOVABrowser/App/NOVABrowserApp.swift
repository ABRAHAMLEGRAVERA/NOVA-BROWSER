import SwiftUI

@main
struct NOVABrowserApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            MainBrowserView(viewModel: viewModel)
        }
    }
}
