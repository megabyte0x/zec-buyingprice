import SwiftUI

@main
struct ZECBuyingPriceApp: App {
    @State private var model = WalletModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model).frame(minWidth: 1120, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 850)
        Settings { SettingsView(model: model) }
    }
}
