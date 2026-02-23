import Foundation

public enum SpikeJSONCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SpikeDateCodec.string(from: date))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = SpikeDateCodec.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid RFC3339 timestamp: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}

public enum NDJSONSpikeLogError: Error {
    case invalidUTF8Line
}

public final actor NDJSONSpikeLogger {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = SpikeJSONCodec.makeEncoder()
    }

    public func append(_ entry: SpikeLogEntry) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) {
            _ = fileManager.createFile(atPath: fileURL.path, contents: Data())
        }

        var line = try encoder.encode(entry)
        line.append(0x0A) // newline separator for NDJSON

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }

        handle.seekToEndOfFile()
        handle.write(line)
    }

    public func readAll() throws -> [SpikeLogEntry] {
        let parser = NDJSONSpikeLogParser()
        return try parser.parse(fileURL: fileURL)
    }
}

public struct NDJSONSpikeLogParser {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = SpikeJSONCodec.makeDecoder()) {
        self.decoder = decoder
    }

    public func parse(fileURL: URL) throws -> [SpikeLogEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }

    public func parse(data: Data) throws -> [SpikeLogEntry] {
        guard !data.isEmpty else {
            return []
        }

        let source = String(decoding: data, as: UTF8.self)
        var entries: [SpikeLogEntry] = []
        for rawLine in source.split(whereSeparator: \.isNewline) {
            guard let lineData = String(rawLine).data(using: .utf8) else {
                throw NDJSONSpikeLogError.invalidUTF8Line
            }
            entries.append(try decoder.decode(SpikeLogEntry.self, from: lineData))
        }
        return entries
    }
}

enum SpikeDateCodec {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let defaultFormatter = ISO8601DateFormatter()
        defaultFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        defaultFormatter.formatOptions = [.withInternetDateTime]
        return defaultFormatter.date(from: value)
    }
}
