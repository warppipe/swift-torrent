import Foundation
import NIOCore
import NIOPosix

/// Async disk I/O using NIO thread pool.
public actor DiskIO {
    private let basePath: String
    private let fileStorage: FileStorage
    private let threadPool: NIOThreadPool

    public init(basePath: String, fileStorage: FileStorage, threadPoolSize: Int = 4) {
        self.basePath = basePath
        self.fileStorage = fileStorage
        self.threadPool = NIOThreadPool(numberOfThreads: threadPoolSize)
        self.threadPool.start()
    }

    deinit {
        try? threadPool.syncShutdownGracefully()
    }

    /// Write a piece to disk.
    public func writePiece(index: Int, data: Data) async throws {
        let slices = fileStorage.fileSlices(forPiece: index)

        var dataOffset = 0
        for slice in slices {
            let filePath = (basePath as NSString).appendingPathComponent(slice.path)

            // Ensure directory exists
            let dir = (filePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            // Create file if needed
            if !FileManager.default.fileExists(atPath: filePath) {
                FileManager.default.createFile(atPath: filePath, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
            defer { try? handle.close() }
            handle.seek(toFileOffset: UInt64(slice.offset))
            let chunk = data.subdata(in: dataOffset..<dataOffset + slice.length)
            handle.write(chunk)
            dataOffset += slice.length
        }
    }

    /// Read a piece from disk.
    public func readPiece(index: Int) async throws -> Data {
        let slices = fileStorage.fileSlices(forPiece: index)
        var result = Data()

        for slice in slices {
            let filePath = (basePath as NSString).appendingPathComponent(slice.path)
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
            defer { try? handle.close() }
            handle.seek(toFileOffset: UInt64(slice.offset))
            let chunk = handle.readData(ofLength: slice.length)
            result.append(chunk)
        }

        return result
    }

    /// Ensure all files exist with correct sizes.
    public func allocateFiles() throws {
        for file in fileStorage.files {
            let filePath = (basePath as NSString).appendingPathComponent(file.path)
            let dir = (filePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: filePath) {
                FileManager.default.createFile(atPath: filePath, contents: nil)
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
                handle.truncateFile(atOffset: UInt64(file.length))
                try handle.close()
            }
        }
    }
}
