// MARK: - NetworkError.swift

// Jellyswarrm — LGPL-2.1-or-later

import Foundation

public enum NetworkError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case decodingError(String)
    case encodingError
    case networkUnavailable
    case timeout
    case sslError
    case redirectLoop
    case emptyResponse
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The server URL is invalid. Please check your server address."
        case .unauthorized:
            "Authentication failed. Please check your username and password."
        case .forbidden:
            "Access denied. You don't have permission to perform this action."
        case .notFound:
            "The requested resource was not found on the server."
        case let .serverError(code):
            "The server returned an error (HTTP \(code)). Please try again later."
        case let .decodingError(detail):
            "Failed to parse the server response: \(detail)"
        case .encodingError:
            "Failed to encode the request."
        case .networkUnavailable:
            "No network connection. Please check your internet or local network."
        case .timeout:
            "The request timed out. Your server may be offline or unreachable."
        case .sslError:
            "A secure connection could not be established. Check your server's SSL certificate."
        case .redirectLoop:
            "Too many redirects. Check your server URL configuration."
        case .emptyResponse:
            "The server returned an empty response."
        case let .custom(message):
            message
        }
    }

    /// Initialize from an HTTP status code
    public static func from(statusCode: Int) -> NetworkError? {
        switch statusCode {
        case 200 ..< 300: nil
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 400 ..< 500: .serverError(statusCode)
        case 500 ..< 600: .serverError(statusCode)
        default: .serverError(statusCode)
        }
    }
}
