// MARK: - NetworkError.swift
// Jellyswarrm — GPL v3 with App Store exception

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
            return "The server URL is invalid. Please check your server address."
        case .unauthorized:
            return "Authentication failed. Please check your username and password."
        case .forbidden:
            return "Access denied. You don't have permission to perform this action."
        case .notFound:
            return "The requested resource was not found on the server."
        case .serverError(let code):
            return "The server returned an error (HTTP \(code)). Please try again later."
        case .decodingError(let detail):
            return "Failed to parse the server response: \(detail)"
        case .encodingError:
            return "Failed to encode the request."
        case .networkUnavailable:
            return "No network connection. Please check your internet or local network."
        case .timeout:
            return "The request timed out. Your server may be offline or unreachable."
        case .sslError:
            return "A secure connection could not be established. Check your server's SSL certificate."
        case .redirectLoop:
            return "Too many redirects. Check your server URL configuration."
        case .emptyResponse:
            return "The server returned an empty response."
        case .custom(let message):
            return message
        }
    }

    /// Initialize from an HTTP status code
    public static func from(statusCode: Int) -> NetworkError? {
        switch statusCode {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 400..<500: return .serverError(statusCode)
        case 500..<600: return .serverError(statusCode)
        default: return .serverError(statusCode)
        }
    }
}
