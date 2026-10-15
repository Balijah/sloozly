import Foundation

// MARK: - API Service

final class APIService {
    static let shared = APIService()
    
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private init() {
        guard let url = URL(string: Constants.apiBaseURL) else {
            fatalError("Invalid API base URL")
        }
        self.baseURL = url
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.apiTimeout
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Request Building
    
    private func buildRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token if available
        if let token = KeychainManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add body if present
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }
        
        return request
    }
    
    // MARK: - Request Execution
    
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        retryOnAuthFailure: Bool = true
    ) async throws -> T {
        let request = try buildRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: queryItems
        )
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle error status codes
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            if retryOnAuthFailure {
                return try await retryWithFreshToken(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    queryItems: queryItems
                )
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.conflict(errorResponse?.message ?? "Conflict")
        case 422:
            let errorResponse = try? decoder.decode(ValidationErrorResponse.self, from: data)
            throw APIError.validation(errorResponse?.errors ?? [:])
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.unknown(errorResponse?.message ?? "Unknown error")
        }
        
        // Decode response
        let apiResponse = try decoder.decode(APIResponse<T>.self, from: data)
        return apiResponse.data
    }
    
    /// Refresh the Firebase auth token and retry the request once.
    private func retryWithFreshToken<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        queryItems: [URLQueryItem]?
    ) async throws -> T {
        do {
            _ = try await AuthService.shared.refreshToken()
        } catch {
            throw APIError.tokenRefreshFailed(error)
        }
        return try await request(
            endpoint: endpoint,
            method: method,
            body: body,
            queryItems: queryItems,
            retryOnAuthFailure: false
        )
    }
    
    func requestVoid(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        retryOnAuthFailure: Bool = true
    ) async throws {
        let request = try buildRequest(endpoint: endpoint, method: method, body: body)
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 && retryOnAuthFailure {
            do {
                _ = try await AuthService.shared.refreshToken()
            } catch {
                throw APIError.tokenRefreshFailed(error)
            }
            try await requestVoid(
                endpoint: endpoint,
                method: method,
                body: body,
                retryOnAuthFailure: false
            )
            return
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.unknown(errorResponse?.message ?? "Request failed")
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Response Wrapper

struct APIResponse<T: Decodable>: Decodable {
    let status: String
    let data: T
}

struct ErrorResponse: Decodable {
    let status: String
    let message: String
}

struct ValidationErrorResponse: Decodable {
    let status: String
    let message: String
    let errors: [String: [String]]
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case conflict(String)
    case validation([String: [String]])
    case serverError(Int)
    case unknown(String)
    case networkError(Error)
    case tokenRefreshFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Please sign in again"
        case .forbidden:
            return "Access denied"
        case .notFound:
            return "Resource not found"
        case .conflict(let message):
            return message
        case .validation(let errors):
            let messages = errors.values.flatMap { $0 }
            return messages.joined(separator: "\n")
        case .serverError(let code):
            return "Server error (\(code))"
        case .unknown(let message):
            return message
        case .networkError(let error):
            return error.localizedDescription
        case .tokenRefreshFailed(let error):
            return "Authentication refresh failed: \(error.localizedDescription)"
        }
    }
    
    /// Whether this error is transient and the request should be retried.
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError:
            return true
        default:
            return false
        }
    }
}

// MARK: - API Endpoints Extension

extension APIService {
    
    // MARK: - Auth
    
    func register(firebaseToken: String, timezone: String = TimeZone.current.identifier) async throws -> User {
        struct RegisterRequest: Codable {
            let firebaseToken: String
            let timezone: String
        }
        
        return try await request(
            endpoint: "auth/register",
            method: .post,
            body: RegisterRequest(firebaseToken: firebaseToken, timezone: timezone)
        )
    }
    
    func getMe() async throws -> User {
        try await request(endpoint: "auth/me")
    }
    
    func deleteAccount() async throws {
        try await requestVoid(endpoint: "auth/me", method: .delete)
    }
    
    func updateFCMToken(_ token: String) async throws {
        struct FCMTokenRequest: Codable {
            let fcmToken: String
        }
        try await requestVoid(
            endpoint: "auth/fcm-token",
            method: .put,
            body: FCMTokenRequest(fcmToken: token)
        )
    }
    
    // MARK: - Bank
    
    func createLinkToken() async throws -> String {
        struct LinkTokenResponse: Decodable {
            let linkToken: String
        }
        let response: LinkTokenResponse = try await request(endpoint: "bank/link-token", method: .post)
        return response.linkToken
    }
    
    func exchangeBankToken(publicToken: String, accountId: String, mandateAccepted: Bool = true) async throws -> BankAccountInfo {
        struct ExchangeRequest: Codable {
            let publicToken: String
            let accountId: String
            let mandateAccepted: Bool
        }
        return try await request(
            endpoint: "bank/exchange-token",
            method: .post,
            body: ExchangeRequest(publicToken: publicToken, accountId: accountId, mandateAccepted: mandateAccepted)
        )
    }
    
    func getBankStatus() async throws -> BankStatusResponse {
        try await request(endpoint: "bank/status")
    }
    
    func unlinkBank() async throws {
        try await requestVoid(endpoint: "bank/unlink", method: .delete)
    }
    
    // MARK: - Alarms
    
    func listAlarms() async throws -> [AlarmModel] {
        struct AlarmsResponse: Decodable {
            let alarms: [AlarmModel]
            let count: Int
        }
        let response: AlarmsResponse = try await request(endpoint: "alarms")
        return response.alarms
    }
    
    func createAlarm(_ request: CreateAlarmRequest) async throws -> AlarmModel {
        try await self.request(endpoint: "alarms", method: .post, body: request)
    }
    
    func updateAlarm(id: String, _ request: UpdateAlarmRequest) async throws -> AlarmModel {
        try await self.request(endpoint: "alarms/\(id)", method: .put, body: request)
    }
    
    func deleteAlarm(id: String) async throws {
        try await requestVoid(endpoint: "alarms/\(id)", method: .delete)
    }
    
    // MARK: - Penalties
    
    func triggerPenalty(alarmId: String, occurrenceId: String, snoozeNumber: Int) async throws -> TriggerPenaltyResponse {
        try await request(
            endpoint: "penalties/trigger",
            method: .post,
            body: TriggerPenaltyRequest(alarmId: alarmId, occurrenceId: occurrenceId, snoozeNumber: snoozeNumber)
        )
    }
    
    func getPenaltyHistory(page: Int = 1, limit: Int = 20) async throws -> PenaltyHistoryResponse {
        try await request(
            endpoint: "penalties/history",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
    }
    
    func getPenaltyStats() async throws -> PenaltyStats {
        try await request(endpoint: "penalties/stats")
    }
}

// MARK: - Response Types

struct BankStatusResponse: Decodable {
    let linked: Bool
    let account: BankAccountInfo?
}

struct PenaltyHistoryResponse: Decodable {
    let penalties: [Penalty]
    let pagination: Pagination
    
    struct Pagination: Decodable {
        let page: Int
        let limit: Int
        let total: Int
        let totalPages: Int
    }
}
