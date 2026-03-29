import Foundation

enum RequestAuthorization {
    case none
    case currentUser
    case bearer(String)
}

struct APIRequestDescriptor {
    let url: URL
    var method: HTTPMethod = .GET
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?
    var authorization: RequestAuthorization = .none

    init(
        url: URL,
        method: HTTPMethod = .GET,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        authorization: RequestAuthorization = .none
    ) {
        self.url = url
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.authorization = authorization
    }

    static func jsonBody(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    static func jsonBody<Body: Encodable>(_ value: Body) throws -> Data {
        try JSONEncoder().encode(AnyEncodable(value))
    }
}

final class APIRequestExecutor {
    static let shared = APIRequestExecutor()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func perform(_ descriptor: APIRequestDescriptor) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: descriptor.url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !descriptor.queryItems.isEmpty {
            components.queryItems = descriptor.queryItems
        }
        guard let resolvedURL = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = descriptor.method.rawValue

        var headers = descriptor.headers
        if headers["Accept"] == nil {
            headers["Accept"] = "application/json"
        }

        switch descriptor.authorization {
        case .none:
            break
        case .currentUser:
            let token = try await OIDCAuthManager.shared.getAccessToken()
            headers["Authorization"] = "Bearer \(token)"
        case .bearer(let token):
            headers["Authorization"] = "Bearer \(token)"
        }

        if let body = descriptor.body {
            request.httpBody = body
            if headers["Content-Type"] == nil {
                headers["Content-Type"] = "application/json"
            }
        }

        request.allHTTPHeaderFields = headers

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }

    func performDecodable<Response: Decodable>(
        _ descriptor: APIRequestDescriptor,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response {
        let (data, response) = try await perform(descriptor)
        guard (200...299).contains(response.statusCode) else {
            throw APIError.statusCode(response.statusCode, data)
        }
        return try decoder.decode(Response.self, from: data)
    }
}
