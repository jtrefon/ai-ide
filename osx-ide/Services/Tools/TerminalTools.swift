//
//  TerminalTools.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

/// Run a shell command
struct RunCommandTool: AITool {
    let name = "run_command"
    let description = "Execute a shell command in the terminal."
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to execute."
                ],
                "working_directory": [
                    "type": "string",
                    "description": "The directory to run the command in (optional)."
                ]
            ],
            "required": ["command"]
        ]
    }
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String else {
            throw AppError.aiServiceError("Missing 'command' argument for run_command")
        }
        
        let workingDirectory = arguments["working_directory"] as? String
        
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = ["-c", command]
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        if let wd = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return """
            Exit Code: \(process.terminationStatus)
            Output:
            \(output)
            """
        } catch {
            return "Failed to run command: \(error.localizedDescription)"
        }
    }
}
