import Foundation

// Helper for encoding heterogeneous types
internal struct AnyCodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let val = value as? String {
            try container.encode(val)
        } else if let val = value as? Int {
            try container.encode(val)
        } else if let val = value as? Double {
            try container.encode(val)
        } else if let val = value as? Bool {
            try container.encode(val)
        } else if let val = value as? [String: Any] {
            var mapContainer = encoder.container(keyedBy: DynamicKey.self)
            for (key, nestedValue) in val {
                try mapContainer.encode(AnyCodable(nestedValue), forKey: DynamicKey(stringValue: key)!)
            }
        } else if let val = value as? [Any] {
            var arrContainer = encoder.unkeyedContainer()
            for nestedValue in val {
                try arrContainer.encode(AnyCodable(nestedValue))
            }
        } else {
            try container.encodeNil()
        }
    }

    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
