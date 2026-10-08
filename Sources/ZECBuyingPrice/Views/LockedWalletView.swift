import SwiftUI

struct LockedWalletView: View {
    @Bindable var model: WalletModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 38)).foregroundStyle(LabTheme.burgundy)
            Text(model.connected ? "Your wallet interface is locked." : "Your wallet is locked.").font(LabTheme.heading(30))
            Text("Unlock with Touch ID or your Mac login password to view your wallet. Mainnet syncing continues after switching apps while the application remains open.")
                .font(.system(size: 14)).foregroundStyle(LabTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: model.connect) {
                Label(model.authenticating ? "Unlocking…" : (model.connected ? "Unlock interface" : "Unlock wallet"), systemImage: "touchid")
            }
            .buttonStyle(LabButtonStyle(primary: true))
            .keyboardShortcut(.return)
            .disabled(model.authenticating)
            Label(model.connected ? "Wallet interface locked • sync session open" : "Authenticate to start mainnet syncing", systemImage: "desktopcomputer")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            if model.connected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mainnet scan • \(Int(model.progress * 100))%")
                        .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    ProgressView(value: model.progress).progressViewStyle(ScanProgressBarStyle())
                    Text(model.scanBlockSummary)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(LabTheme.muted)
                    Button("Stop syncing & lock wallet") { model.lock() }
                        .buttonStyle(LabButtonStyle())
                }
            }
            Text("Switching apps, hiding or minimizing locks the interface while syncing continues. Quitting or closing the last wallet window stops syncing and locks protected storage. Sleeping or locking your Mac also ends the sync session.")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect a different wallet", action: model.disconnect)
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(LabTheme.burgundy)
                .disabled(model.authenticating)
        }
        .padding(32).frame(maxWidth: .infinity, alignment: .leading).labPanel()
        Spacer()
    }
}
