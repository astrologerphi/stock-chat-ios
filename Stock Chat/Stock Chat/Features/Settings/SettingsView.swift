import SwiftUI

/// App-wide presentation state shared through the environment.
@Observable
final class AppRouter {
    var isSettingsPresented = false
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(APIService.allCases) { service in
                    APIKeySection(service: service)
                }
                Section {
                } footer: {
                    Text("Keys are stored in this device's Keychain and are only sent to their own service. A key saved here replaces the one built in from `.secrets`.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

private struct APIKeySection: View {
    let service: APIService
    @Environment(MarketData.self) private var marketData
    @State private var draft = ""
    @State private var reveal = false
    @State private var current: ResolvedAPIKey?
    @State private var check: APIKeyCheck?
    @State private var isChecking = false
    @FocusState private var isFocused: Bool

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Section {
            HStack {
                Group {
                    if reveal {
                        TextField("Paste API key", text: $draft)
                    } else {
                        SecureField("Paste API key", text: $draft)
                    }
                }
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("\(service.rawValue)-key-field")

                Button(reveal ? "Hide Key" : "Show Key", systemImage: reveal ? "eye.slash" : "eye") {
                    reveal.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .glassListRow()

            LabeledContent("Current Key") {
                if let current {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(current.masked).monospaced()
                        Text(current.source.label).font(.caption)
                    }
                } else {
                    Text("Not set")
                }
            }
            .glassListRow()

            HStack {
                Text("Status")
                Spacer()
                statusLabel
            }
            .glassListRow()

            Button("Save Key", systemImage: "key.fill", action: save)
                .disabled(trimmedDraft.isEmpty)
                .glassListRow()

            Button("Test Key", systemImage: "checkmark.shield") {
                Task { await test(trimmedDraft.isEmpty ? current?.value : trimmedDraft) }
            }
            .disabled(isChecking || (trimmedDraft.isEmpty && current == nil))
            .glassListRow()

            if current?.source == .settings {
                Button("Remove Saved Key", systemImage: "trash", role: .destructive, action: remove)
                    .glassListRow()
            }
        } header: {
            Text(service.displayName)
        } footer: {
            Text(LocalizedStringKey(service.usage))
        }
        .onAppear { current = Secrets.key(for: service) }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch check {
        case _ where isChecking:
            Text("Checking…").foregroundStyle(.secondary)
        case .valid:
            status("Valid", systemImage: "checkmark.circle.fill", color: .gain)
        case .rejected:
            status("Rejected", systemImage: "xmark.octagon.fill", color: .loss)
        case .failed(let message):
            status("Couldn't verify", systemImage: "exclamationmark.triangle.fill", color: .orange)
                .accessibilityHint(message)
        case nil:
            Text("Not tested").foregroundStyle(.secondary)
        }
    }

    private func status(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        let key = trimmedDraft
        guard !key.isEmpty else { return }
        guard Secrets.save(key, for: service) else {
            check = .failed("Couldn't save the key to the Keychain.")
            return
        }
        draft = ""
        reveal = false
        isFocused = false
        keyChanged()
        Task { await test(key) }
    }

    private func remove() {
        Secrets.removeSavedKey(for: service)
        check = nil
        keyChanged()
    }

    private func keyChanged() {
        current = Secrets.key(for: service)
        if service == .fmp { marketData.reloadProviders() }
    }

    private func test(_ key: String?) async {
        guard let key, !key.isEmpty else { return }
        isChecking = true
        check = await APIKeyValidator.check(key, for: service)
        isChecking = false
    }
}

#Preview {
    SettingsView()
        .environment(MarketData.live())
}
