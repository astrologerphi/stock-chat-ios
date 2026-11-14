import SwiftUI

extension View {
    /// Flat, opaque card surface. Liquid Glass is reserved for the system bars at the top and bottom.
    func flatSurface(cornerRadius: CGFloat = 22) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
    }

    /// Flat page background matching inset-grouped lists.
    func flatPageBackground() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

/// A rounded flat panel for grouping content.
struct Card<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flatSurface(cornerRadius: cornerRadius)
    }
}

struct SectionHeader: View {
    var title: String
    var systemImage: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
            }
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?
    @Environment(AppRouter.self) private var router: AppRouter?

    private var isAPIKeyError: Bool {
        router != nil && [MarketDataError.missingAPIKey, .invalidAPIKey].contains { $0.errorDescription == message }
    }

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAPIKeyError {
                    Button("Settings") { router?.isSettingsPresented = true }
                        .buttonStyle(.borderedProminent)
                } else if let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
