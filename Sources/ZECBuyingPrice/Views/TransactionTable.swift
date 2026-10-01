import SwiftUI
import AcquisitionCore

struct TransactionTable: View {
    @Bindable var model: WalletModel
    @State private var editedMovement: Movement?
    @State private var manualPrice = ""
    @State private var priceError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("The movement ledger").font(LabTheme.heading(23))
                    Text("\(model.movements.filter(\.included).count) selected of \(model.movements.count) movements")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(LabTheme.muted)
                    TextField("Search transaction or direction", text: $model.search).textFieldStyle(.plain)
                        .accessibilityLabel("Search transaction or direction")
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).help("Clear search")
                    }
                }.font(.system(size: 12)).padding(10).frame(width: 250).labPanel()
            }
            Table(model.visibleMovements) {
                TableColumn("Use") { movement in
                    Toggle("Include transaction", isOn: Binding(
                        get: { movement.included },
                        set: { model.setIncluded(movement.id, $0) }))
                        .toggleStyle(.checkbox).labelsHidden()
                }.width(32)
                TableColumn("Date") { movement in Text(movement.date, style: .date).font(.system(size: 11)) }.width(90)
                TableColumn("Status") { movement in
                    Text(movement.confirmed ? "Confirmed" : "Pending")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(movement.confirmed ? LabTheme.ink : LabTheme.burgundy)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(movement.confirmed ? LabTheme.blue.opacity(0.4) : LabTheme.parchment, in: RoundedRectangle(cornerRadius: 4))
                }.width(82)
                TableColumn("Movement") { movement in
                    Label(movement.direction == .received ? "Received" : "Sent",
                        systemImage: movement.direction == .received ? "arrow.down.left" : "arrow.up.right")
                        .foregroundStyle(movement.direction == .received ? LabTheme.ink : LabTheme.burgundy)
                        .font(.system(size: 11))
                }.width(82)
                TableColumn("ZEC") { movement in
                    Text(WalletModel.number(movement.quantity, digits: 8)).font(.system(size: 11, design: .monospaced))
                }.width(106)
                TableColumn("USD / ZEC") { movement in
                    Button(movement.price.map { "$" + WalletModel.number($0) } ?? "Add price") {
                        editedMovement = movement
                        manualPrice = movement.price.map { "\($0)" } ?? ""
                        priceError = nil
                    }.buttonStyle(.borderless).foregroundStyle(LabTheme.burgundy)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .help("Edit this movement's acquisition price")
                }.width(85)
                TableColumn("USD value") { movement in
                    Text(movement.price.map { "$" + WalletModel.number($0 * movement.quantity) } ?? "Unavailable")
                        .font(.system(size: 11, design: .monospaced))
                }.width(95)
                TableColumn("Transaction") { movement in
                    Text(movement.id.split(separator: ":").first.map(String.init) ?? movement.id)
                        .lineLimit(1).font(.system(size: 10, design: .monospaced)).foregroundStyle(LabTheme.muted)
                        .textSelection(.enabled)
                        .help("\(movement.id)\nNetwork fee: \(WalletModel.number(movement.feeZatoshis.map { Decimal($0) / 100_000_000 }, digits: 8)) ZEC")
                }.width(min: 90, ideal: 125)
            }
            .scrollContentBackground(.hidden).background(LabTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LabTheme.line))
            .overlay {
                if model.visibleMovements.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: model.movements.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 29, weight: .light)).foregroundStyle(LabTheme.burgundy)
                        Text(model.movements.isEmpty ? "The notebook is waiting." : "No matching movements")
                            .font(LabTheme.heading(23))
                        Text(model.movements.isEmpty ? "Your movements will appear after the wallet scan finishes." : "Try a transaction ID, “received”, or “sent”.")
                            .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                        if !model.search.isEmpty {
                            Button("Clear search") { model.search = "" }.buttonStyle(LabButtonStyle())
                        }
                    }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LabTheme.paper).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 28)
                }
            }
            Text("Select movements to include them. Click a price to enter your actual acquisition cost. Selected sends reduce holdings at the running average.")
                .font(.system(size: 10)).foregroundStyle(LabTheme.muted).lineSpacing(3)
        }
        .sheet(item: $editedMovement) { movement in
            VStack(alignment: .leading, spacing: 20) {
                LabCaption(text: "Adjust your observations")
                Text("Override acquisition price").font(LabTheme.heading(27))
                Text("Enter the actual USD price per ZEC for this movement. This replaces the daily market estimate.")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted).lineSpacing(4)
                LabField(title: "USD per ZEC") { TextField("e.g. 42.50", text: $manualPrice) }
                if let priceError { Text(priceError).font(.caption).foregroundStyle(LabTheme.burgundy) }
                HStack {
                    Button("Cancel") { editedMovement = nil }.buttonStyle(LabButtonStyle()).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save price") {
                        guard let value = Decimal(string: manualPrice), value > 0, !value.isNaN else {
                            priceError = "Enter a positive USD price."; return
                        }
                        model.error = nil
                        model.setManualPrice(movement.id, text: manualPrice)
                        if model.error == nil { editedMovement = nil }
                        else { priceError = model.error }
                    }.buttonStyle(LabButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                }
            }.padding(28).frame(width: 430).background(LabTheme.ivory)
                .foregroundStyle(LabTheme.ink).preferredColorScheme(.light)
        }
    }
}
