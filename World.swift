import Foundation

enum FlatWorld {
    static let radius = 3
    static let sectionMask: UInt16 = 0x0001
    static let spawn = (x: 8.5, y: 5.0, z: 8.5)

    static func column() -> Data {
        var data = Data(capacity: 8192 + 2048 + 2048 + 256)

        for y in 0 ..< 16 {
            let value = UInt16(block(atHeight: y)) << 4
            for _ in 0 ..< 256 {
                data.append(UInt8(value & 0xFF))
                data.append(UInt8(value >> 8))
            }
        }

        data.append(Data(repeating: 0xFF, count: 2048))
        data.append(Data(repeating: 0xFF, count: 2048))
        data.append(Data(repeating: 1, count: 256))

        return data
    }

    private static func block(atHeight y: Int) -> UInt8 {
        switch y {
        case 0: 7
        case 1, 2: 3
        case 3: 2
        default: 0
        }
    }
}
