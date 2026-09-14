import Foundation
import UIKit

enum Telemetry {
    static func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    static func motd() -> String {
        "§aRunning on an \(UIDevice.current.model)\n§7\(model) §8· §e\(battery) §8· §7iOS \(UIDevice.current.systemVersion)"
    }

    static var battery: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "battery n/a" }
        let percent = Int((level * 100).rounded())
        switch UIDevice.current.batteryState {
        case .charging, .full: return "\(percent)% charging"
        default: return "\(percent)%"
        }
    }

    static var model: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { raw in
            raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) } ?? "unknown"
        }
        return marketingNames[identifier] ?? identifier
    }

    private static let marketingNames: [String: String] = {
        let devices: [String: [String]] = [
            "iPhone 11": ["iPhone12,1"],
            "iPhone 11 Pro": ["iPhone12,3"],
            "iPhone 11 Pro Max": ["iPhone12,5"],
            "iPhone SE (2nd gen)": ["iPhone12,8"],
            "iPhone 12 mini": ["iPhone13,1"],
            "iPhone 12": ["iPhone13,2"],
            "iPhone 12 Pro": ["iPhone13,3"],
            "iPhone 12 Pro Max": ["iPhone13,4"],
            "iPhone 13 mini": ["iPhone14,4"],
            "iPhone 13": ["iPhone14,5"],
            "iPhone 13 Pro": ["iPhone14,2"],
            "iPhone 13 Pro Max": ["iPhone14,3"],
            "iPhone SE (3rd gen)": ["iPhone14,6"],
            "iPhone 14": ["iPhone14,7"],
            "iPhone 14 Plus": ["iPhone14,8"],
            "iPhone 14 Pro": ["iPhone15,2"],
            "iPhone 14 Pro Max": ["iPhone15,3"],
            "iPhone 15": ["iPhone15,4"],
            "iPhone 15 Plus": ["iPhone15,5"],
            "iPhone 15 Pro": ["iPhone16,1"],
            "iPhone 15 Pro Max": ["iPhone16,2"],
            "iPhone 16": ["iPhone17,3"],
            "iPhone 16 Plus": ["iPhone17,4"],
            "iPhone 16 Pro": ["iPhone17,1"],
            "iPhone 16 Pro Max": ["iPhone17,2"],
            "iPhone 16e": ["iPhone17,5"],
            "iPhone 17": ["iPhone18,3"],
            "iPhone 17 Pro": ["iPhone18,1"],
            "iPhone 17 Pro Max": ["iPhone18,2"],
            "iPhone Air": ["iPhone18,4"],
            "iPad mini (5th gen)": ["iPad11,1", "iPad11,2"],
            "iPad mini (6th gen)": ["iPad14,1", "iPad14,2"],
            "iPad mini (A17 Pro)": ["iPad16,1", "iPad16,2"],
            "iPad (8th gen)": ["iPad11,6", "iPad11,7"],
            "iPad (9th gen)": ["iPad12,1", "iPad12,2"],
            "iPad (10th gen)": ["iPad13,18", "iPad13,19"],
            "iPad (A16)": ["iPad15,7", "iPad15,8"],
            "iPad Air (3rd gen)": ["iPad11,3", "iPad11,4"],
            "iPad Air (4th gen)": ["iPad13,1", "iPad13,2"],
            "iPad Air (5th gen)": ["iPad13,16", "iPad13,17"],
            "iPad Air 11\" (M2)": ["iPad14,8", "iPad14,9"],
            "iPad Air 13\" (M2)": ["iPad14,10", "iPad14,11"],
            "iPad Air 11\" (M3)": ["iPad15,3", "iPad15,4"],
            "iPad Air 13\" (M3)": ["iPad15,5", "iPad15,6"],
            "iPad Pro 11\" (1st gen)": ["iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4"],
            "iPad Pro 12.9\" (3rd gen)": ["iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8"],
            "iPad Pro 11\" (2nd gen)": ["iPad8,9", "iPad8,10"],
            "iPad Pro 12.9\" (4th gen)": ["iPad8,11", "iPad8,12"],
            "iPad Pro 11\" (M1)": ["iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7"],
            "iPad Pro 12.9\" (M1)": ["iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"],
            "iPad Pro 11\" (M2)": ["iPad14,3", "iPad14,4"],
            "iPad Pro 12.9\" (M2)": ["iPad14,5", "iPad14,6"],
            "iPad Pro 11\" (M4)": ["iPad16,3", "iPad16,4"],
            "iPad Pro 13\" (M4)": ["iPad16,5", "iPad16,6"],
            "Simulator": ["arm64", "x86_64"]
        ]
        var map: [String: String] = [:]
        for (name, identifiers) in devices {
            for identifier in identifiers { map[identifier] = name }
        }
        return map
    }()
}
