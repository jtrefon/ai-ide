#!/usr/bin/env swift

import Foundation
import AppKit

// Simple test to verify terminal manager can handle keyboard input
print("🧪 Testing Terminal Manager Keyboard Input...")

// Create terminal manager
let terminalManager = TerminalManager()

var testResults: [String] = []

// Set up callback to monitor what happens
terminalManager.onScreenUpdate = { content, cursor in
    let screenText = content.map { row in
        row.map { String($0.char) }.joined()
    }.joined(separator: "\n")
    
    print("📺 Terminal output:")
    print(screenText)
    print("---")
    
    if screenText.contains("top") {
        testResults.append("✅ Terminal received 'top' command")
    }
    
    if screenText.contains("$") && !screenText.contains("top") {
        testResults.append("✅ Terminal shows shell prompt")
    }
}

// Initialize terminal
print("🔧 Initializing terminal...")
terminalManager.initialize()

// Wait a moment for initialization
RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))

// Test typing "top"
print("⌨️  Simulating 'top' command...")

// Create key event for 't'
let tEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: NSPoint(x: 100, y: 100),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "t",
    charactersIgnoringModifiers: "t",
    isARepeat: false,
    keyCode: 17
)!

let handled1 = terminalManager.handleKeyPress(tEvent)
print("🔘 't' key handled: \(handled1)")

// Create key event for 'o'
let oEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: NSPoint(x: 100, y: 100),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "o",
    charactersIgnoringModifiers: "o",
    isARepeat: false,
    keyCode: 31
)!

let handled2 = terminalManager.handleKeyPress(oEvent)
print("🔘 'o' key handled: \(handled2)")

// Create key event for 'p'
let pEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: NSPoint(x: 100, y: 100),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "p",
    charactersIgnoringModifiers: "p",
    isARepeat: false,
    keyCode: 35
)!

let handled3 = terminalManager.handleKeyPress(pEvent)
print("🔘 'p' key handled: \(handled3)")

// Press enter
let enterEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: NSPoint(x: 100, y: 100),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "\r",
    charactersIgnoringModifiers: "\r",
    isARepeat: false,
    keyCode: 36
)!

let handled4 = terminalManager.handleKeyPress(enterEvent)
print("🔘 Enter key handled: \(handled4)")

// Wait for command to execute
RunLoop.main.run(until: Date(timeIntervalSinceNow: 3.0))

// Test Ctrl+C to interrupt
print("⌨️  Simulating Ctrl+C to interrupt...")
let ctrlCEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: NSPoint(x: 100, y: 100),
    modifierFlags: .control,
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "c",
    charactersIgnoringModifiers: "c",
    isARepeat: false,
    keyCode: 8
)!

let handled5 = terminalManager.handleKeyPress(ctrlCEvent)
print("🔘 Ctrl+C handled: \(handled5)")

// Wait for final results
RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))

// Print test results
print("\n📊 TEST RESULTS:")
for result in testResults {
    print(result)
}

if testResults.isEmpty {
    print("❌ No keyboard input was handled by terminal!")
    print("This indicates the terminal is not properly receiving keyboard events.")
} else {
    print("✅ Terminal is handling some keyboard input")
}

print("\n🏁 Test completed")
