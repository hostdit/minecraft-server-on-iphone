import Foundation

struct PacketReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func varInt() -> Int32? {
        var result: Int32 = 0
        var shift = 0
        while shift < 35 {
            guard offset < bytes.count else { return nil }
            let byte = bytes[offset]
            offset += 1
            result |= Int32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func string() -> String? {
        guard let length = varInt(), length >= 0 else { return nil }
        let end = offset + Int(length)
        guard end <= bytes.count else { return nil }
        let slice = bytes[offset ..< end]
        offset = end
        return String(decoding: slice, as: UTF8.self)
    }

    mutating func uint16() -> UInt16? {
        guard offset + 2 <= bytes.count else { return nil }
        let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        offset += 2
        return value
    }

    mutating func int64() -> Int64? {
        guard offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for i in 0 ..< 8 {
            value = value << 8 | UInt64(bytes[offset + i])
        }
        offset += 8
        return Int64(bitPattern: value)
    }
}

struct PacketStream {
    private var buffer = Data()

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func next() -> Data? {
        var reader = PacketReader(buffer)
        guard let length = reader.varInt(), length >= 0 else { return nil }
        let header = reader.offset
        let total = header + Int(length)
        guard buffer.count >= total else { return nil }
        let body = buffer.subdata(in: buffer.startIndex + header ..< buffer.startIndex + total)
        buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + total)
        return body
    }
}

enum Packet {
    static func varInt(_ value: Int32) -> Data {
        var remaining = UInt32(bitPattern: value)
        var out = Data()
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    static func string(_ value: String) -> Data {
        let utf8 = Data(value.utf8)
        return varInt(Int32(utf8.count)) + utf8
    }

    static func int64(_ value: Int64) -> Data {
        bigEndian(value)
    }

    static func uint8(_ value: UInt8) -> Data {
        Data([value])
    }

    static func bool(_ value: Bool) -> Data {
        Data([value ? 1 : 0])
    }

    static func uint16(_ value: UInt16) -> Data {
        bigEndian(value)
    }

    static func int32(_ value: Int32) -> Data {
        bigEndian(value)
    }

    static func float(_ value: Float) -> Data {
        bigEndian(value.bitPattern)
    }

    static func double(_ value: Double) -> Data {
        bigEndian(value.bitPattern)
    }

    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func position(_ x: Int32, _ y: Int32, _ z: Int32) -> Data {
        let packed = (Int64(x) & 0x3FFFFFF) << 38 | (Int64(y) & 0xFFF) << 26 | (Int64(z) & 0x3FFFFFF)
        return int64(packed)
    }

    static func frame(id: Int32, body: Data) -> Data {
        let payload = varInt(id) + body
        return varInt(Int32(payload.count)) + payload
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
