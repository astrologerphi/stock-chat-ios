import SwiftUI

/// Soft animated mesh gradient that gives Liquid Glass surfaces something to refract.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = .blue

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120) / 120 * 2 * .pi)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5 + 0.08 * sin(t), 0], [1, 0],
                    [0, 0.5 + 0.06 * cos(t)], [0.5 + 0.1 * cos(t), 0.45 + 0.1 * sin(t)], [1, 0.5 - 0.06 * sin(t)],
                    [0, 1], [0.5 - 0.08 * sin(t), 1], [1, 1],
                ],
                colors: colors
            )
        }
        .ignoresSafeArea()
    }

    private var colors: [Color] {
        if colorScheme == .dark {
            [
                .black, Color(red: 0.05, green: 0.08, blue: 0.20), .black,
                Color(red: 0.03, green: 0.14, blue: 0.22), tint.opacity(0.35), Color(red: 0.12, green: 0.05, blue: 0.22),
                .black, Color(red: 0.02, green: 0.10, blue: 0.12), .black,
            ]
        } else {
            [
                Color(red: 0.93, green: 0.96, blue: 1.0), Color(red: 0.86, green: 0.92, blue: 1.0), Color(red: 0.95, green: 0.93, blue: 1.0),
                Color(red: 0.85, green: 0.97, blue: 0.96), tint.opacity(0.22), Color(red: 0.93, green: 0.88, blue: 1.0),
                Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.88, green: 0.96, blue: 0.98), Color(red: 0.96, green: 0.96, blue: 1.0),
            ]
        }
    }
}

/// A rounded Liquid Glass panel for grouping content.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAPIKeyError {
                    Button("Settings") { router?.isSettingsPresented = true }
                        .buttonStyle(.glassProminent)
                } else if let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(.glass)
                }
            }
        }
    }
}

extension View {
    /// Translucent row background so the app's mesh gradient shows through inset-grouped lists.
    func glassListRow() -> some View {
        listRowBackground(Rectangle().fill(.thinMaterial))
    }
}
