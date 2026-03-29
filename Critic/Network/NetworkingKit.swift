//  Critic
//
//  Created by chinni Rayapudi on 8/16/25.
//


import Foundation
import Combine

// MARK: - Core

public enum HTTPMethod: String { case GET, POST, PUT, PATCH, DELETE }

public enum APIError: Error, LocalizedError {
    case invalidURL, invalidRequest, invalidResponse
    case statusCode(Int, Data?)
    case transport(Error)
    case decoding(Error)
    case encoding(Error)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidRequest: return "Invalid Request"
        case .invalidResponse: return "Invalid Response"
        case .statusCode(let c, _): return "HTTP \(c)"
        case .transport(let e): return "Transport error: \(e.localizedDescription)"
        case .decoding(let e): return "Decoding failed: \(e.localizedDescription)"
        case .encoding(let e): return "Encoding failed: \(e.localizedDescription)"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Endpoint

public protocol Endpoint {
    associatedtype Response: Decodable
    var path: String { get }
    var method: HTTPMethod { get }
    var query: [URLQueryItem]? { get }
    var headers: [String:String]? { get }
    var body: Encodable? { get }
    var decoder: JSONDecoder { get }
}

public extension Endpoint {
    var query: [URLQueryItem]? { nil }
    var headers: [String:String]? { nil }
    var body: Encodable? { nil }
    var decoder: JSONDecoder { JSONDecoder() }
}

// MARK: - Request building

public protocol RequestBuilding {
    func buildRequest(baseURL: URL, endpoint: any Endpoint) throws -> URLRequest
}

public final class DefaultRequestBuilder: RequestBuilding {
    public init() {}
    public func buildRequest(baseURL: URL, endpoint: any Endpoint) throws -> URLRequest {
        guard var url = URL(string: endpoint.path, relativeTo: baseURL) else { throw APIError.invalidURL }
        if let q = endpoint.query, var comps = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            comps.queryItems = q
            url = comps.url ?? url
        }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue

        var hdr = ["Accept":"application/json"]
        endpoint.headers?.forEach { hdr[$0.key] = $0.value }
        req.allHTTPHeaderFields = hdr

        if let enc = endpoint.body {
            do {
                req.httpBody = try JSONEncoder().encode(AnyEncodable(enc))
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch { throw APIError.encoding(error) }
        }
        return req
    }
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ e: Encodable) { _encode = e.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Adapters / Validators

public protocol RequestAdapter { func adapt(_ request: URLRequest) -> URLRequest }
public protocol ResponseValidator { func validate(data: Data, response: URLResponse) throws }

public struct StatusCodeValidator: ResponseValidator {
    public init() {}
    public func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.statusCode(http.statusCode, data) }
    }
}

public struct LoggingAdapter: RequestAdapter {
    public init() {}
    public func adapt(_ request: URLRequest) -> URLRequest {
        #if DEBUG
        print("➡️ \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
        #endif
        return request
    }
}

public struct LoggingValidator: ResponseValidator {
    public init() {}
    public func validate(data: Data, response: URLResponse) throws {
        #if DEBUG
        if let http = response as? HTTPURLResponse {
            print("⬅️ [\(http.statusCode)] \(http.url?.absoluteString ?? "")")
        }
        #endif
    }
}

// MARK: - Retry

public protocol RetryPolicy { func delay(for attempt: Int, error: APIError) -> DispatchTimeInterval? }

public struct ExponentialBackoffRetry: RetryPolicy {
    public let maxAttempts: Int
    public let base: Double
    public init(maxAttempts: Int = 3, base: Double = 0.6) {
        self.maxAttempts = maxAttempts
        self.base = base
    }
    public func delay(for attempt: Int, error: APIError) -> DispatchTimeInterval? {
        guard attempt < maxAttempts else { return nil }
        switch error {
        case .transport:
            let seconds = pow(2.0, Double(attempt)) * base
            return .milliseconds(Int(seconds * 1000))
        case .statusCode(let code, _) where code >= 500:
            let seconds = pow(2.0, Double(attempt)) * base
            return .milliseconds(Int(seconds * 1000))
        default:
            return nil
        }
    }
}

// MARK: - Client

public protocol NetworkClient {
    func execute<E: Endpoint>(_ endpoint: E) -> AnyPublisher<E.Response, APIError>
}

public final class URLSessionClient: NetworkClient {
    private let baseURL: URL
    private let session: URLSession
    private let builder: RequestBuilding
    private let adapters: [RequestAdapter]
    private let validators: [ResponseValidator]
    private let retry: RetryPolicy?

    public init(baseURL: URL,
                session: URLSession = .shared,
                builder: RequestBuilding = DefaultRequestBuilder(),
                adapters: [RequestAdapter] = [LoggingAdapter()],
                validators: [ResponseValidator] = [StatusCodeValidator(), LoggingValidator()],
                retry: RetryPolicy? = ExponentialBackoffRetry()) {
        self.baseURL = baseURL
        self.session = session
        self.builder = builder
        self.adapters = adapters
        self.validators = validators
        self.retry = retry
    }

    public func execute<E>(_ endpoint: E) -> AnyPublisher<E.Response, APIError> where E : Endpoint {
        do {
            var request = try builder.buildRequest(baseURL: baseURL, endpoint: endpoint)
            adapters.forEach { request = $0.adapt(request) }

            // Capture stored properties into locals to avoid explicit 'self' in nested closures
            let validators = self.validators
            let retryPolicy = self.retry

            func run(_ attempt: Int) -> AnyPublisher<E.Response, APIError> {
                session.dataTaskPublisher(for: request)
                    .tryMap { output -> Data in
                        for v in validators { try v.validate(data: output.data, response: output.response) }
                        return output.data
                    }
                    .mapError { err in
                        if (err as? URLError)?.code == .cancelled { return APIError.cancelled }
                        return (err as? APIError) ?? APIError.transport(err)
                    }
                    .decode(type: E.Response.self, decoder: endpoint.decoder)
                    .mapError { (e: Error) -> APIError in
                        (e as? APIError) ?? APIError.decoding(e)
                    }
                    .catch { error -> AnyPublisher<E.Response, APIError> in
                        guard let retryPolicy,
                              let delay = retryPolicy.delay(for: attempt, error: error) else {
                            return Fail(error: error).eraseToAnyPublisher()
                        }
                        return Just(())
                            .delay(for: .init(delay), scheduler: DispatchQueue.global())
                            .setFailureType(to: APIError.self)
                            .flatMap { run(attempt + 1) }
                            .eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            }
            return run(0)
        } catch let e as APIError {
            return Fail(error: e).eraseToAnyPublisher()
        } catch {
            return Fail(error: .invalidRequest).eraseToAnyPublisher()
        }
    }
}

