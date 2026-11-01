import Foundation

/// Extracts validated frames from arbitrary BLE fragmentation/coalescing.
/// Bytes are copied into a zero-based array: Foundation Data slices need not start at zero.
public struct JKStreamAssembler {
    private var buffer: [UInt8] = []
    public private(set) var rejectedFrames = 0
    public var bufferedByteCount: Int { buffer.count }
    public init() {}
    public mutating func reset() { buffer.removeAll(keepingCapacity: true); rejectedFrames = 0 }
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(contentsOf: data)
        var frames: [Data] = []
        while buffer.count >= 2 {
            let modern = buffer.count >= 4 && Array(buffer.prefix(4)) == [0x55, 0xAA, 0xEB, 0x90]
            let legacy = buffer[0] == 0x4E && buffer[1] == 0x57
            if modern {
                guard buffer.count >= 300 else { break }
                let frame = Data(buffer.prefix(300))
                if JKModernCodec.isValid(frame: frame) { frames.append(frame); buffer.removeFirst(300) }
                else { rejectedFrames += 1; buffer.removeFirst() }
            } else if legacy {
                guard buffer.count >= 4 else { break }
                let total = (Int(buffer[2]) << 8 | Int(buffer[3])) + 2
                guard (21...4096).contains(total) else { rejectedFrames += 1; buffer.removeFirst(); continue }
                guard buffer.count >= total else {
                    // A lost/corrupt legacy length must not hide a subsequent complete BLE frame.
                    if let start = nextCompleteFrameStart() { rejectedFrames += 1; buffer.removeFirst(start); continue }
                    break
                }
                let frame = Data(buffer.prefix(total))
                if JKPacketCodec.isValid(data: frame) { frames.append(frame); buffer.removeFirst(total) }
                else { rejectedFrames += 1; buffer.removeFirst() }
            } else {
                // Keep an incomplete modern header across fragment boundaries.
                if buffer[0] == 0x55 && buffer.count < 4 && Array([UInt8](arrayLiteral: 0x55, 0xAA, 0xEB, 0x90).prefix(buffer.count)) == buffer { break }
                if let next = buffer.dropFirst().firstIndex(where: { $0 == 0x55 || $0 == 0x4E }) { buffer.removeFirst(next) }
                else { buffer = Array(buffer.suffix(1)); break }
            }
        }
        if buffer.count > 4096 { buffer = Array(buffer.suffix(3)); rejectedFrames += 1 }
        return frames
    }

    private func nextCompleteFrameStart() -> Int? {
        guard buffer.count >= 22 else { return nil }
        for i in 1..<(buffer.count - 1) {
            if i + 300 <= buffer.count, buffer[i] == 0x55,
               JKModernCodec.isValid(frame: Data(buffer[i..<(i + 300)])) { return i }
            if i + 4 <= buffer.count, buffer[i] == 0x4E, buffer[i + 1] == 0x57 {
                let length = (Int(buffer[i + 2]) << 8 | Int(buffer[i + 3])) + 2
                if (21...4096).contains(length), i + length <= buffer.count,
                   JKPacketCodec.isValid(data: Data(buffer[i..<(i + length)])) { return i }
            }
        }
        return nil
    }
}
