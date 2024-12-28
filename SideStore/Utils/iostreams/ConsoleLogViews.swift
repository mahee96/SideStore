//
//  ConsoleLogView 2.swift
//  AltStore
//
//  Created by Magesh K on 28/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//



struct ConsoleLogView: View {
    
    @StateObject private var logger = ConsoleLog(bufferSize: 100)
    
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                logContent
                Divider()
                toolbarContent
            }
            .navigationTitle("minimuxer")
            .navigationBarTitleDisplayMode(.inline)
//            .onAppear {
//                logger.startCapturing()
//            }
            .onDisappear {
                logger.stopCapturing()
            }
        }
        .onChange(of: presentationMode.wrappedValue.isPresented) { isPresented in
            if !isPresented {
                logger.stopCapturing()
            }
        }
    }

    private var logContent: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(logger.logBuffer)
                        .font(.custom("SFMono-Regular", size: 14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .cornerRadius(8)
                        .onChange(of: logger.logBuffer) { _ in
                            proxy.scrollTo(9999, anchor: .bottom) // Scroll to a high number to always go to the bottom
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.edgesIgnoringSafeArea(.all)) // Optional: Full-screen background
        }
    }

    private var toolbarContent: some View {
        HStack {
//            shareButton
            Spacer()
            closeButton
        }
        .padding()
        .background(Color(UIColor.systemGray6))
    }

//    private var shareButton: some View {
//        SwiftUI.Button(action: shareLogs) {
//            Image(systemName: "square.and.arrow.up")
//                .font(.title2)
//                .foregroundColor(.blue)
//        }
//    }

    private var closeButton: some View {
        SwiftUI.Button(action: {
            logger.stopCapturing()
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "xmark")
                .font(.title2)
                .foregroundColor(.blue)
        }
    }

//    private func shareLogs() {
//        let logsText = logs.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
//        let activityVC = UIActivityViewController(activityItems: [logsText], applicationActivities: nil)
//        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//           let rootVC = windowScene.windows.first?.rootViewController {
//            rootVC.present(activityVC, animated: true, completion: nil)
//        }
//    }
}

class UnBufferedMemoryLogStream: OutputStream {
    private let fileOutputStream: FileOutputStream
    private let textBuffer: AbstractTextBuffer
    private let updateHandler: (String) -> Void
    
    init(fileOutputStream: FileOutputStream, bufferSize: Int, onUpdate: @escaping (String) -> Void) {
        self.fileOutputStream = fileOutputStream
//        self.textBuffer = FixedSizeTextBuffer(maxSize: bufferSize)
        self.textBuffer = AppendingTextBuffer()
        self.updateHandler = onUpdate
    }
    
    func write(_ data: Data) {
        // Write to file
        fileOutputStream.write(data)
        
        // Write to buffer
        if let text = String(data: data, encoding: .utf8) {
            textBuffer.append(text)
            // Notify the view about the updated buffer
            updateHandler(textBuffer.content)
        }
    }
    
    func flush() {
        fileOutputStream.flush()
    }
    
    func close() {
        fileOutputStream.close()
    }
}

protocol TextBuffer{
    func append(_ text: String)
}
    
class AbstractTextBuffer: TextBuffer{
    var buffer: String = ""
    
    // swift doesn't have abstract keyword :(
    public required init(){}
        
    func append(_ text: String){
        // Append the new text
        buffer.append(text)
    }
    
    // Get the current content of the buffer
    var content: String {
        return buffer
    }
    
    // Clear the buffer
    func clear() {
        buffer.removeAll()
    }
}

class FixedSizeTextBuffer: AbstractTextBuffer {
    private let maxSize: Int
    
    public init(maxSize: Int) {
        self.maxSize = maxSize
        super.init()
    }
    
    public required init() {
        fatalError("init() has not been implemented")
    }
    
    // Append text to the buffer
    public override func append(_ text: String) {
        let totalSize = buffer.count + text.count
        
        // Only remove excess if the total size exceeds maxSize
        if totalSize > maxSize {
            let excess = totalSize - maxSize
            let safeExcess = min(excess, buffer.count)
            buffer.removeFirst(safeExcess)
        }
        
        // Append the new text
        buffer.append(text)
    }
}

//class AppendingTextBuffer: AbstractTextBuffer{}
typealias AppendingTextBuffer = AbstractTextBuffer
