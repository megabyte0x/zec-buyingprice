import SwiftUI
import AcquisitionCore

struct ContentView: View {
    @Bindable var model: WalletModel
    @State private var confirmsReset = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 22) {
                header
                if !model.connected {
                    SetupView(model: model)
                } else {
                    AcquisitionSummary(model: model)
                    scanStatus
                    TransactionTable(model: model).frame(maxHeight: .infinity)
                }
                if let error = model.error {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error).textSelection(.enabled)
                    }.font(.system(size: 12)).foregroundStyle(LabTheme.burgundy)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(LabTheme.parchment.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                footer
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LabTheme.ivory).foregroundStyle(LabTheme.ink).tint(LabTheme.burgundy)
        .preferredColorScheme(.light)
        .alert("Reset this wallet's local history?", isPresented: $confirmsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetLocalHistory() }
        } message: {
            Text("The current scan database and transaction choices will be archived on this Mac. Reconnecting starts a fresh scan. Your viewing key remains in Keychain.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "flask.fill").font(.system(size: 24)).foregroundStyle(LabTheme.burgundy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZEC").font(.system(size: 22, weight: .bold, design: .serif))
                    Text("BUYING PRICE").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4)
                }
            }.padding(.bottom, 39)
            LabCaption(text: "Workspace").padding(.leading, 12).padding(.bottom, 13)
            Label(model.connected ? "Acquisition lab" : "Connect wallet", systemImage: "square.grid.2x2")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(LabTheme.burgundy)
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(LabTheme.burgundy.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            SettingsLink { Label("Lab settings", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).font(.system(size: 13)).padding(13).padding(.top, 4)
                .help("Configure wallet server and historical price access")
            Spacer()
            if model.connected {
                GeometryReader { geometry in
                    ScientistArtwork().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.bottom, 16)
            }
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "eye").font(.system(size: 24)).foregroundStyle(LabTheme.burgundy)
                Text("Your keys.\nYour research.").font(LabTheme.heading(15))
                    .fixedSize(horizontal: false, vertical: true)
                Text("View-only analysis.\nNo spending permissions.").font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineSpacing(4)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(LabTheme.ivory.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 7) {
                Image(systemName: "desktopcomputer")
                Text("LOCAL WORKSPACE")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(LabTheme.muted).padding(.top, 22)
        }.padding(20).frame(width: 190).frame(maxHeight: .infinity)
            .background(LabTheme.parchment.opacity(0.55))
            .overlay(alignment: .trailing) { Rectangle().fill(LabTheme.line).frame(width: 1) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.connected ? "Your acquisition notebook" : "Welcome to the lab.").font(LabTheme.heading(29))
                Text(model.connected ? "Follow the movements. Find your average." : "Good observations make better decisions.")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
            Spacer()
            Label("Zcash mainnet", systemImage: "network").font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(LabTheme.blue.opacity(0.4), in: Capsule())
        }
    }

    private var scanStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: model.scanComplete ? "checkmark.seal" : "waveform.path").foregroundStyle(LabTheme.burgundy)
                Text(model.status).font(.system(size: 12)).textSelection(.enabled)
                Spacer()
                Text("\(Int(model.progress * 100))%").font(.system(size: 12, weight: .semibold, design: .monospaced))
                Button("Pause", action: model.pause).buttonStyle(LabButtonStyle()).disabled(model.scanComplete && !model.busy)
                Button("Resume", action: model.resume).buttonStyle(LabButtonStyle()).disabled(model.busy)
            }
            ProgressView(value: model.progress).tint(LabTheme.burgundy)
        }.padding(16).labPanel()
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(LabTheme.muted)
            Text("Daily market prices are estimates, not exchange purchase records.")
                .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
            Spacer()
            if model.connected {
                Menu {
                    Button("Retry historical prices", action: model.refreshPrices)
                    Button("Change wallet", action: model.disconnect)
                    Divider()
                    Button("Reset local history…", role: .destructive) { confirmsReset = true }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 18)) }
                .menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                .help("Wallet actions")
            }
        }
    }
}

struct AcquisitionSummary: View {
    @Bindable var model: WalletModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                LabCaption(text: "Average acquisition price")
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(average).font(.system(size: 45, weight: .medium, design: .serif)).monospacedDigit()
                    Text("USD / ZEC").font(.system(size: 11, design: .monospaced)).foregroundStyle(LabTheme.muted)
                }
                Label(summaryStatus, systemImage: "function")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                if case .failure(let error) = model.ledger {
                    Text(error.localizedDescription).font(.caption).foregroundStyle(LabTheme.burgundy)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                metric("Selected remaining", remaining, "ZEC")
                Rectangle().fill(LabTheme.line).frame(height: 1)
                metric("Acquisition value", value, "USD estimate")
            }.padding(24).frame(width: 235).background(LabTheme.blue.opacity(0.32))
        }.background(LabTheme.paper).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LabTheme.line))
    }
    private var average: String {
        if case .success(let ledger) = model.ledger, model.canDisplayAverage, let price = ledger.averagePrice {
            return "$" + WalletModel.number(price)
        }
        return "—"
    }
    private var summaryStatus: String {
        guard model.canDisplayAverage else { return "Available after analysis completes" }
        if case .success(let ledger) = model.ledger {
            return ledger.averagePrice == nil ? "No selected remaining holdings" : "Based on your selected movements"
        }
        return "Review the selected movements below"
    }
    private var remaining: String {
        if case .success(let ledger) = model.ledger { return WalletModel.number(Decimal(ledger.zatoshis) / 100_000_000, digits: 8) }
        return "—"
    }
    private var value: String {
        if case .success(let ledger) = model.ledger, model.canDisplayAverage { return "$" + WalletModel.number(ledger.value) }
        return "—"
    }
    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(LabTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 21, weight: .medium)).monospacedDigit()
                Text(unit).font(.system(size: 9, design: .monospaced)).foregroundStyle(LabTheme.muted)
            }
        }
    }
}
