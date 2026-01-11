//
//  AIService.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation

public struct AIServiceResponse: Sendable {
    public let content: String?
    public let toolCalls: [AIToolCall]?
}

public protocol AIService: Sendable {
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse
    func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse
    func explainCode(_ code: String) async throws -> String
    func refactorCode(_ code: String, instructions: String) async throws -> String
    func generateCode(_ prompt: String) async throws -> String
    func fixCode(_ code: String, error: String) async throws -> String
}

public extension AIService {
    func sendMessageResult(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?
    ) async -> Result<AIServiceResponse, AppError> {
        do {
            let response = try await sendMessage(message, context: context, tools: tools, mode: mode)
            return .success(response)
        } catch {
            return .failure(Self.mapToAppError(error, operation: "sendMessage"))
        }
    }

    func sendMessageResult(
        _ message: String,
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async -> Result<AIServiceResponse, AppError> {
        do {
            let response = try await sendMessage(message, context: context, tools: tools, mode: mode, projectRoot: projectRoot)
            return .success(response)
        } catch {
            return .failure(Self.mapToAppError(error, operation: "sendMessageWithProjectRoot"))
        }
    }

    func sendMessageResult(
        _ messages: [ChatMessage],
        context: String?,
        tools: [AITool]?,
        mode: AIMode?,
        projectRoot: URL?
    ) async -> Result<AIServiceResponse, AppError> {
        do {
            let response = try await sendMessage(messages, context: context, tools: tools, mode: mode, projectRoot: projectRoot)
            return .success(response)
        } catch {
            return .failure(Self.mapToAppError(error, operation: "sendMessageHistory"))
        }
    }

    private static func mapToAppError(_ error: Error, operation: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .aiServiceError("AIService.\(operation) failed: \(error.localizedDescription)")
    }
}