import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Large hero card for the top story.
struct NewsHeroCard: View {
    var article: NewsArticle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NewsImage(url: article.image, symbol: article.symbol)
                .frame(height: 220)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                NewsMeta(article: article, onImage: true)
                Text(article.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(18)
        }
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 28))
        .contentShape(.rect(cornerRadius: 28))
    }
}

struct NewsRow: View {
    var article: NewsArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                NewsMeta(article: article)
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let text = article.text, !text.isEmpty {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if article.image != nil {
                NewsImage(url: article.image, symbol: article.symbol)
                    .frame(width: 84, height: 84)
                    .clipShape(.rect(cornerRadius: 16))
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }
}

struct NewsMeta: View {
    var article: NewsArticle
    var onImage = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = article.symbol {
                Text(symbol)
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(onImage ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.tint.opacity(0.15)), in: .capsule)
                    .foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            }
            Text(article.publisher ?? article.site ?? "")
                .lineLimit(1)
            Text("·")
            Text(article.publishedDate, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(onImage ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
    }
}

struct NewsImage: View {
    var url: URL?
    var symbol: String?

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.indigo.opacity(0.6), .teal.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "newspaper.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
    }
}

/// Vertical feed of articles; tapping opens the article in Safari.
struct NewsFeed: View {
    var articles: [NewsArticle]
    var heroFirst = true
    @State private var openURL: URL?

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                Button {
                    openURL = article.url
                } label: {
                    if heroFirst && index == 0 {
                        NewsHeroCard(article: article)
                    } else {
                        NewsRow(article: article)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $openURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
}
