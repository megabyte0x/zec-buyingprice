import SwiftUI
import AppKit

@main
struct ApplicationMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--vault-guard") {
            VaultGuardMain.run()
        }
        if CommandLine.arguments.contains("--wallet-worker") {
            WalletWorkerMain.run()
        }
        ZECBuyingPriceApp.main()
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: WalletModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.lock() == false ? .terminateCancel : .terminateNow
    }
}

struct ZECBuyingPriceApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @State private var model = WalletModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model).frame(minWidth: 1120, minHeight: 680)
                .background(WalletWindowTracking())
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1240, height: 850)
        Settings { SettingsView(model: model) }
    }
}
