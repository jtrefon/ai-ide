//
//  ErrorManager.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI
import Combine

/// Centralized error management for the application
@MainActor
class ErrorManager: ObservableObject, ErrorManagerProtocol {
    @Published var currentError: AppError?
    @Published var showErrorAlert: Bool = false
    @Published var errorHistory: [AppError] = []
    
    private let maxHistoryCount = AppConstants.FileSystem.maxHistoryCount
    
    /// Handle an error with appropriate UI feedback
    func handle(_ error: AppError) {
        currentError = error
        showErrorAlert = true
        
        // Add to history for logging
        errorHistory.append(error)
        if errorHistory.count > maxHistoryCount {
            errorHistory.removeFirst()
        }
        
        // Log the error
        logError(error)
        
        // Auto-dismiss info and warning errors after delay
        if error.severity == .info || error.severity == .warning {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Time.errorAutoDismissDelay) { [weak self] in
                if self?.currentError?.severity == error.severity {
                    self?.dismissError()
                }
            }
        }
    }
    
    /// Handle generic Error by converting to AppError
    func handle(_ error: Error, context: String = "") {
        let appError: AppError
        if let appErr = error as? AppError {
            appError = appErr
        } else {
            appError = .unknown("\(context): \(error.localizedDescription)")
        }
        handle(appError)
    }
    
    /// Dismiss current error
    func dismissError() {
        currentError = nil
        showErrorAlert = false
    }
    
    /// Get recent errors for debugging
    func getRecentErrors() -> [AppError] {
        return errorHistory
    }
    
    /// Clear error history
    func clearErrorHistory() {
        errorHistory.removeAll()
    }
    
    private func logError(_ error: AppError) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(error.severity)] \(error.localizedDescription)"

        Task {
            await AppLogger.shared.error(category: .error, message: "app.error", metadata: [
                "severity": String(describing: error.severity),
                "description": error.localizedDescription
            ])
        }
        
        #if DEBUG
        print(logMessage)
        #endif
    }
}

/// Extension for easy error handling in other classes
extension ErrorManager {
    /// Wrap error-prone operations with automatic error handling
    func handleError<T>(_ operation: () throws -> T, context: String = "") -> T? {
        do {
            return try operation()
        } catch {
            handle(error, context: context)
            return nil
        }
    }
    
    /// Async version of error handling
    func handleError<T>(_ operation: () async throws -> T, context: String = "") async -> T? {
        do {
            return try await operation()
        } catch {
            await MainActor.run {
                handle(error, context: context)
            }
            return nil
        }
    }
}
