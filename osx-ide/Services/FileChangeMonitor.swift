import Foundation
import Darwin

final class FileChangeMonitor {
    private let url: URL
    private let eventMask: DispatchSource.FileSystemEvent
    private let queue: DispatchQueue
    private let handler: (DispatchSource.FileSystemEvent) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var isActive = false

    init(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .attrib, .rename, .delete],
        queue: DispatchQueue = DispatchQueue(label: "FileChangeMonitor"),
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) {
        self.url = url
        self.eventMask = eventMask
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: eventMask,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.handler(source.data)
        }
        source.setCancelHandler { [weak self] in
            self?.closeDescriptor()
        }
        self.source = source
        isActive = true
        source.resume()
    }

    func stop() {
        guard isActive else {
            closeDescriptor()
            return
        }
        isActive = false
        source?.cancel()
        source = nil
    }

    private func closeDescriptor() {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}
