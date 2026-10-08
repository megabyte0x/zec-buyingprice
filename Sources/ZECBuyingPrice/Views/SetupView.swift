import SwiftUI

struct SetupView: View {
    @Bindable var model: WalletModel
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LabCaption(text: "The acquisition laboratory")
                Text("A little curiosity.\nA clearer cost basis.")
                    .font(LabTheme.heading(34)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                Text("Trace your Zcash history and discover the story behind your average acquisition price.")
                    .font(.system(size: 14)).foregroundStyle(LabTheme.muted)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                Rectangle().fill(LabTheme.line).frame(height: 1).padding(.vertical, 25)
                HStack(spacing: 12) {
                    Image(systemName: "key.horizontal").font(.system(size: 18)).foregroundStyle(LabTheme.burgundy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect a viewing-only wallet").font(.system(size: 16, weight: .semibold))
                        Text("Your first experiment starts here.").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    }
                }.padding(.bottom, 22)
                LabField(title: "Unified Full Viewing Key") {
                    SecureField("Paste your mainnet viewing key", text: $model.key)
                        .accessibilityLabel("Unified Full Viewing Key")
                }
                HStack(alignment: .top, spacing: 16) {
                    LabField(title: "Wallet birthday") {
                        DatePicker("Wallet birthday", selection: $model.birthday, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.field)
                    }
                    LabField(title: "Block height · optional") {
                        TextField("e.g. 1,200,000", text: $model.heightOverride)
                            .accessibilityLabel("Birthday block height, optional")
                    }
                }.padding(.top, 16)
                Text("Choose a date before your first transaction. A block height takes precedence over the date.")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineSpacing(3).padding(.top, 10)
                HStack(spacing: 12) {
                    Button(action: model.connect) {
                        HStack { Text(model.busy ? "Unlocking the laboratory…" : "Authenticate & start analysis"); Image(systemName: "arrow.right") }
                    }.buttonStyle(LabButtonStyle(primary: true)).keyboardShortcut(.return)
                        .disabled(model.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                    if model.busy { ProgressView().controlSize(.small) }
                }.padding(.top, 23)
                if model.busy || model.effectiveBirthday > 0 {
                    Text(model.status).font(.caption).foregroundStyle(LabTheme.muted).padding(.top, 8)
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(LabTheme.burgundy)
                    Text("Protected with Secure Enclave and encrypted storage. Touch ID or your Mac login password is required. A viewing key reveals wallet history but cannot spend funds.")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(LabTheme.parchment.opacity(0.35), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 23)
                Spacer(minLength: 0)
            }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.automatic).frame(maxWidth: .infinity)
            GeometryReader { geometry in
                ScientistArtwork().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.frame(width: 330)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Observe. Calculate. Understand.").font(LabTheme.heading(22))
                        Text("A private workspace for your ZEC.").font(.system(size: 11, design: .monospaced))
                    }.foregroundStyle(LabTheme.ivory).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22).background(LabTheme.burgundy)
                }
        }
        .background(LabTheme.paper).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LabTheme.line))
    }
}
