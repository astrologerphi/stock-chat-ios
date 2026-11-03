import Foundation

nonisolated enum APIKeyCheck: Equatable, Sendable {
    case valid
    case rejected
    case failed(String)
}

/// Makes a cheap authenticated request to confirm a key is accepted by its service.
nonisolated enum APIKeyValidator {
    static func check(_ key: String, for service: APIService, session: URLSession = .shared) async -> APIKeyCheck {
        var request: URLRequest
        switch service {
        case .fmp:
            var components = URLComponents(string: "https://financialmodelingprep.com/stable/quote")!
            components.queryItems = [URLQueryItem(name: "symbol", value: "AAPL"), URLQueryItem(name: "apikey", value: key)]
            request = URLRequest(url: components.url!)
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.timeoutInterval = 15
        do {
            let (_, response) = try await session.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300: return .valid
            case 400, 401, 403: return .rejected
            case let status: return .failed("The server returned an error (\(status)).")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
