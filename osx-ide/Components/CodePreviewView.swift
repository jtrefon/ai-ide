//
//  CodePreviewView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI

struct CodePreviewView: View {
    let code: String
    let language: String?
    let title: String
    @State private var isCopied = false
    
    init(code: String, language: String? = nil, title: String = "Code Preview") {
        self.code = code
        self.language = language
        self.title = title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let language = language {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(action: copyCode) {
                    HStack {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.blue)
            }
            
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.top, 4)
    }
    
    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
}

struct CodePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        CodePreviewView(code: "func helloWorld() {\n    print(\"Hello, World!\")\n}")
            .padding()
    }
}