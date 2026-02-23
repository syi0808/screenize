import SwiftUI

enum BackgroundStyle: Equatable {
    case solid(Color)
    case gradient(GradientStyle)
    case image(URL)

    var rawValue: String {
        switch self {
        case .solid(let color):
            return "solid:\(color.hexString)"
        case .gradient(let style):
            return "gradient:\(style.rawValue)"
        case .image(let url):
            return "image:\(url.absoluteString)"
        }
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return nil }

        let type = String(components[0])
        let value = String(components[1])

        switch type {
        case "solid":
            self = .solid(Color(hex: value) ?? .black)
        case "gradient":
            self = .gradient(GradientStyle(rawValue: value) ?? .defaultGradient)
        case "image":
            if let url = URL(string: value) {
                self = .image(url)
            } else {
                return nil
            }
        default:
            return nil
        }
    }
}

struct GradientStyle: Equatable, RawRepresentable {
    let colors: [Color]
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    var rawValue: String {
        let colorHexes = colors.map { $0.hexString }.joined(separator: ",")
        return "\(colorHexes)|\(startPoint.x),\(startPoint.y)|\(endPoint.x),\(endPoint.y)"
    }

    init(colors: [Color], startPoint: UnitPoint = .topLeading, endPoint: UnitPoint = .bottomTrailing) {
        self.colors = colors
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|")
        guard parts.count == 3 else { return nil }

        let colorHexes = parts[0].split(separator: ",")
        let colors = colorHexes.compactMap { Color(hex: String($0)) }
        guard !colors.isEmpty else { return nil }

        let startParts = parts[1].split(separator: ",")
        let endParts = parts[2].split(separator: ",")

        guard startParts.count == 2, endParts.count == 2,
              let sx = Double(startParts[0]), let sy = Double(startParts[1]),
              let ex = Double(endParts[0]), let ey = Double(endParts[1]) else {
            return nil
        }

        self.colors = colors
        self.startPoint = UnitPoint(x: sx, y: sy)
        self.endPoint = UnitPoint(x: ex, y: ey)
    }

    static let defaultGradient = Self(
        colors: [Color(hex: "#667eea")!, Color(hex: "#764ba2")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sunset = Self(
        colors: [Color(hex: "#ff6b6b")!, Color(hex: "#feca57")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ocean = Self(
        colors: [Color(hex: "#667eea")!, Color(hex: "#00d2d3")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let forest = Self(
        colors: [Color(hex: "#11998e")!, Color(hex: "#38ef7d")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let midnight = Self(
        colors: [Color(hex: "#232526")!, Color(hex: "#414345")!],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let presets: [Self] = [
        .defaultGradient, .sunset, .ocean, .forest, .midnight
    ]
}

// MARK: - Codable

extension BackgroundStyle: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let style = BackgroundStyle(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid BackgroundStyle rawValue: \(rawValue)"
            )
        }
        self = style
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension GradientStyle: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let style = GradientStyle(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid GradientStyle rawValue: \(rawValue)"
            )
        }
        self = style
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// Color+Hex extension is now defined in DesignSystem/DesignColors.swift
