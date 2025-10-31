import Foundation
import CryptoKit

/// File chunk for multi-path transmission
public struct FileChunk: Codable, Identifiable {
    public let id: UUID // Chunk ID
    public let sequence: Int // Sequence number (0-based)
    public let total: Int // Total number of chunks
    public let pathId: UUID? // Which relay path this chunk uses
    public let dataBase64: String // Base64 encoded chunk data
    public let checksum: String // SHA256 checksum
    
    public init(sequence: Int, total: Int, data: Data, pathId: UUID? = nil) {
        self.id = UUID()
        self.sequence = sequence
        self.total = total
        self.pathId = pathId
        self.dataBase64 = data.base64EncodedString()
        self.checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Decode chunk data
    public func decodeData() -> Data? {
        return Data(base64Encoded: dataBase64)
    }
    
    /// Verify checksum
    public func verifyChecksum() -> Bool {
        guard let data = decodeData() else { return false }
        let computed = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return computed == checksum
    }
}

/// Chunked file metadata
public struct ChunkedFile: Codable {
    public let fileId: UUID
    public let fileName: String
    public let mimeType: String
    public let totalSize: Int
    public let totalChunks: Int
    public let chunkSize: Int
    public let senderId: UUID
    public let senderNickname: String
    public let timestamp: TimeInterval
    
    public init(
        fileId: UUID = UUID(),
        fileName: String,
        mimeType: String,
        totalSize: Int,
        totalChunks: Int,
        chunkSize: Int,
        senderId: UUID,
        senderNickname: String
    ) {
        self.fileId = fileId
        self.fileName = fileName
        self.mimeType = mimeType
        self.totalSize = totalSize
        self.totalChunks = totalChunks
        self.chunkSize = chunkSize
        self.senderId = senderId
        self.senderNickname = senderNickname
        self.timestamp = Date().timeIntervalSince1970
    }
}

/// File chunker for splitting files into 100KB chunks for multi-path transfer
@MainActor
public final class FileChunker {
    public static let defaultChunkSize = 100 * 1024 // 100KB
    
    /// Split file into chunks
    public static func chunk(file data: Data, fileName: String, mimeType: String, chunkSize: Int = defaultChunkSize, senderId: UUID, senderNickname: String) -> (ChunkedFile, [FileChunk]) {
        let fileId = UUID()
        let totalSize = data.count
        let totalChunks = Int(ceil(Double(totalSize) / Double(chunkSize)))
        
        let metadata = ChunkedFile(
            fileId: fileId,
            fileName: fileName,
            mimeType: mimeType,
            totalSize: totalSize,
            totalChunks: totalChunks,
            chunkSize: chunkSize,
            senderId: senderId,
            senderNickname: senderNickname
        )
        
        var chunks: [FileChunk] = []
        for i in 0..<totalChunks {
            let start = i * chunkSize
            let end = min(start + chunkSize, totalSize)
            let chunkData = data[start..<end]
            let chunk = FileChunk(sequence: i, total: totalChunks, data: Data(chunkData))
            chunks.append(chunk)
        }
        
        return (metadata, chunks)
    }
    
    /// Reassemble chunks with deduplication and checksum verification
    public static func reassemble(metadata: ChunkedFile, chunks: [FileChunk]) -> Result<Data, ReassemblyError> {
        // Deduplicate by sequence number (keep first valid chunk)
        var uniqueChunks: [Int: FileChunk] = [:]
        for chunk in chunks {
            if chunk.total != metadata.totalChunks {
                return .failure(.mismatchedTotal)
            }
            if let existing = uniqueChunks[chunk.sequence] {
                // Keep the one with valid checksum, or the first if both invalid
                if chunk.verifyChecksum() && !existing.verifyChecksum() {
                    uniqueChunks[chunk.sequence] = chunk
                }
            } else {
                uniqueChunks[chunk.sequence] = chunk
            }
        }
        
        // Check if we have all chunks
        guard uniqueChunks.count == metadata.totalChunks else {
            return .failure(.missingChunks(expected: metadata.totalChunks, received: uniqueChunks.count))
        }
        
        // Verify all checksums
        var verifiedChunks: [Data] = []
        for seq in 0..<metadata.totalChunks {
            guard let chunk = uniqueChunks[seq] else {
                return .failure(.missingSequence(seq))
            }
            
            guard chunk.verifyChecksum() else {
                return .failure(.invalidChecksum(sequence: seq))
            }
            
            guard let data = chunk.decodeData() else {
                return .failure(.decodeError(sequence: seq))
            }
            
            verifiedChunks.append(data)
        }
        
        // Reassemble
        var reassembled = Data()
        for data in verifiedChunks {
            reassembled.append(data)
        }
        
        // Verify final size
        guard reassembled.count == metadata.totalSize else {
            return .failure(.sizeMismatch(expected: metadata.totalSize, actual: reassembled.count))
        }
        
        return .success(reassembled)
    }
}

/// Reassembly errors
public enum ReassemblyError: LocalizedError {
    case mismatchedTotal
    case missingChunks(expected: Int, received: Int)
    case missingSequence(Int)
    case invalidChecksum(sequence: Int)
    case decodeError(sequence: Int)
    case sizeMismatch(expected: Int, actual: Int)
    
    public var errorDescription: String? {
        switch self {
        case .mismatchedTotal:
            return "Total chunk count mismatch"
        case .missingChunks(let expected, let received):
            return "Missing chunks: expected \(expected), received \(received)"
        case .missingSequence(let seq):
            return "Missing sequence number: \(seq)"
        case .invalidChecksum(let seq):
            return "Invalid checksum for sequence \(seq)"
        case .decodeError(let seq):
            return "Failed to decode sequence \(seq)"
        case .sizeMismatch(let expected, let actual):
            return "Size mismatch: expected \(expected), got \(actual)"
        }
    }
}

/// In-memory reassembly buffer
@MainActor
public final class ReassemblyBuffer {
    private var files: [UUID: (ChunkedFile, [Int: FileChunk])] = [:]
    private var timeoutTimer: Timer?
    private let timeout: TimeInterval = 30.0 // 30 seconds to reassemble
    
    // Expose reassembly buffer for BLE chunker
    var reassemblyBuffer: [UUID: [Int: Data]] = [:]
    
    init() {
        startCleanupTimer()
    }
    
    /// Add chunk to reassembly buffer
    public func addChunk(_ chunk: FileChunk, metadata: ChunkedFile) -> Result<Data, ReassemblyError>? {
        let fileId = metadata.fileId
        
        // Initialize if needed
        if files[fileId] == nil {
            files[fileId] = (metadata, [:])
        }
        
        var (meta, chunks) = files[fileId]!
        
        // Add chunk (deduplicate by sequence)
        if let existing = chunks[chunk.sequence] {
            // Keep the one with valid checksum
            if chunk.verifyChecksum() && !existing.verifyChecksum() {
                chunks[chunk.sequence] = chunk
            }
        } else {
            chunks[chunk.sequence] = chunk
        }
        
        files[fileId] = (meta, chunks)
        
        // Try to reassemble if we have all chunks
        if chunks.count == meta.totalChunks {
            let chunkArray = Array(chunks.values).sorted { $0.sequence < $1.sequence }
            let result = FileChunker.reassemble(metadata: meta, chunks: chunkArray)
            
            // Remove from buffer if successful
            if case .success = result {
                files.removeValue(forKey: fileId)
            }
            
            return result
        }
        
        return nil // Not ready yet
    }
    
    /// Clean up stale files
    private func startCleanupTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.cleanupStale()
        }
    }
    
    private func cleanupStale() {
        let now = Date()
        let stale = files.filter { (fileId, value) in
            let (metadata, _) = value
            return now.timeIntervalSince1970 - metadata.timestamp > timeout
        }
        
        for (fileId, _) in stale {
            files.removeValue(forKey: fileId)
        }
    }
    
    deinit {
        timeoutTimer?.invalidate()
    }
}

