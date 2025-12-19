import Foundation
import AppKit

// Mock implementations for dependencies to make this standalone if possible, 
// OR import the necessary files in the compilation command.
// We will assume the files are compiled together.

@main
struct DebugTerminal {
    static func main() {
        print("🔍 Debugging Terminal Display Issue")

        // Test if TerminalManager can be created and initialized
        print("\n1️⃣ Testing TerminalManager creation...")
        
        let terminalManager = TerminalManager { error in
            print("❌ Terminal error: \(error)")
        }
        
        print("✅ TerminalManager created")
        
        // Test initialization
        print("\n2️⃣ Testing terminal initialization...")
        terminalManager.initialize()
        
        // Wait a moment for initialization
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))
        
        print("✅ Terminal initialized")
        
        // Test screen content callback
        print("\n3️⃣ Testing screen content callback...")
        var screenUpdateReceived = false
        
        terminalManager.onScreenUpdate = { content, cursor in
            print("📺 Screen update received!")
            print("   Content rows: \(content.count)")
            print("   Cursor position: \(cursor)")
            
            if !content.isEmpty {
                let firstRow = content[0].map { String($0.char) }.joined()
                print("   First row: '\(firstRow)'")
            }
            
            screenUpdateReceived = true
        }
        
        // Send some test data
        print("\n4️⃣ Testing keyboard input...")
        let testEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: NSPoint(x: 100, y: 100),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "echo test\r",
            charactersIgnoringModifiers: "echo test\r",
            isARepeat: false,
            keyCode: 0
        )
        
        if let event = testEvent {
            let handled = terminalManager.handleKeyPress(event)
            print("✅ Keyboard input handled: \(handled)")
        }
        
        // Wait for response
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 3.0))
        
        if screenUpdateReceived {
            print("✅ Screen content callback working")
        } else {
            print("❌ No screen content received - PTY might not be working")
        }
        
        // Test terminal size
        print("\n5️⃣ Testing terminal size...")
        let size = terminalManager.getSize()
        print("   Terminal size: \(size.rows) rows × \(size.columns) columns")
        
        print("\n🎯 Expected Behavior in App:")
        print("1. Terminal should show shell prompt (e.g., '$ ') immediately")
        print("2. Typing should show characters in terminal")
        print("3. Commands should execute when Enter is pressed")
        print("4. Interactive apps like 'top' should work")

        print("\n🔧 If terminal is blank:")
        print("- Check PTY initialization in TerminalManager")
        print("- Verify shell process is actually running")
        print("- Ensure screenContent is being updated in SwiftUI")
        print("- Check TerminalRenderer is drawing content properly")

        print("\n🏁 Debug completed")
    }
}
