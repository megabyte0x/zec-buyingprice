import SwiftUI

struct SettingsView: View {
    @Bindable var model: WalletModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 23)).foregroundStyle(LabTheme.burgundy)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calibrate your laboratory").font(LabTheme.heading(27))
                    Text("Wallet services & historical observations").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 15) {
                LabCaption(text: "Wallet service")
                HStack(alignment: .top, spacing: 14) {
                    LabField(title: "TLS lightwalletd host") { TextField("zec.rocks", text: $model.host) }
                    LabField(title: "Port") { TextField("443", text: $model.port) }.frame(width: 90)
                }
                Text("Choose a server you trust. Changes apply when you next connect your wallet.")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20).labPanel()
            VStack(alignment: .leading, spacing: 15) {
                LabCaption(text: "Historical prices · CoinGecko")
                LabField(title: "API key · optional") { SecureField("Enter your CoinGecko API key", text: $model.apiKey) }
                Toggle("Use CoinGecko Pro API", isOn: $model.proAPI).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12))
                Text("Free access covers the past year. Older movements may require a paid plan or manual prices. Credentials are saved in Keychain when connecting.")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(20).labPanel()
            Label("Viewing keys use protected encrypted storage. Price API credentials stay in Keychain.", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
        }.padding(28).frame(width: 540).background(LabTheme.ivory)
            .foregroundStyle(LabTheme.ink).tint(LabTheme.burgundy).preferredColorScheme(.light)
    }
}
