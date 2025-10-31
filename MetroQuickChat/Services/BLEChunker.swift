import Foundation

struct BLEFrame: Codable {
    let id: UUID
    let index: Int
    let total: Int
    let payloadBase64: String
}

final class BLEChunker {
    // Increased chunk size for better performance with larger data (images/voice)
    // BLE MTU is typically 512 bytes, but we use 480 to be safe after protocol overhead
    static let maxChunk: Int = 480

    static func chunk(data: Data) -> [Data] {
        let id = UUID()
        let total = Int(ceil(Double(data.count) / Double(maxChunk)))
        var frames: [Data] = []
        for i in 0..<total {
            let start = i * maxChunk
            let end = min(start + maxChunk, data.count)
            let slice = data[start..<end]
            let frame = BLEFrame(id: id, index: i, total: total, payloadBase64: Data(slice).base64EncodedString())
            if let encoded = try? JSONEncoder().encode(frame) { frames.append(encoded) }
        }
        return frames
    }

    static func reassemble(buffer: inout [UUID: [Int: Data]], incoming: Data) -> Data? {
        guard let frame = try? JSONDecoder().decode(BLEFrame.self, from: incoming) else { return nil }
        var map = buffer[frame.id] ?? [:]
        map[frame.index] = Data(base64Encoded: frame.payloadBase64) ?? Data()
        buffer[frame.id] = map
        if map.count == frame.total {
            let ordered = (0..<frame.total).compactMap { map[$0] }
            buffer.removeValue(forKey: frame.id)
            var result = Data()
            for piece in ordered { result.append(piece) }
            return result
        }
        return nil
    }
}


