//
//  Log.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor Log {
    // MARK: - Property
    static let shared = Log()
    static let subsystem = "im.toss.jineun.bot.forge"
    
    private static let _processName: String = {
        let executablePath = CommandLine.arguments.first ?? ""
        let base = (executablePath as NSString).lastPathComponent
        
        return base.isEmpty ? "forge" : base
    }()
    
    private static let _pid: Int = Int(ProcessInfo.processInfo.processIdentifier)
    
    nonisolated(unsafe) private static let _isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return formatter
    }()
    
    private static var processName: String { _processName }
    
    private static var pid: Int { _pid }
    
    private var sinkOverride: URL?
    private var errorSinkOverride: URL?
    private var maxBytes: Int = 0
    
    // MARK: - Initializer
    init() {
    }
    
    // MARK: - Public
    static func isoString(_ date: Date) -> String {
        _isoFormatter.string(from: date)
    }
    
    func setSink(_ url: URL?) {
        sinkOverride = url
    }
    
    func setErrorSink(_ url: URL?) {
        errorSinkOverride = url
    }
    
    func setMaxBytes(_ bytes: Int) {
        maxBytes = bytes
    }
    
    func append(
        _ kind: String,
        _ payload: LogPayload,
        level: LogLevel? = nil,
        category: String,
        message: String = "",
        error: [String: Any]? = nil,
        parameters: [String: JSONValue]? = nil,
        rootID: String? = nil,
        nodeID: String? = nil,
        parentNodeID: String? = nil,
        at: Date? = nil
    ) {
        let timestampNanoseconds: Int64
        
        if let at {
            timestampNanoseconds = Int64(at.timeIntervalSince1970 * 1_000_000_000)
        } else {
            timestampNanoseconds = Self.nowNs()
        }
        
        let level = level ?? Self.inferLevel(kind: kind)
        let effectiveRoot = rootID ?? LogContext.rootID
        let effectiveNode = nodeID ?? LogContext.nodeID
        let effectiveParent = parentNodeID ?? LogContext.parentNodeID
        let effectiveParameters = parameters ?? LogContext.parameters ?? [:]
        let parametersAny: [String: Any] = effectiveParameters.mapValues(Self.jsonValueToAny)
        
        let record: [String: Any] = [
            "timestamp": Self.iso(timestampNanoseconds),
            "ts_ns": timestampNanoseconds,
            "subsystem": Self.subsystem,
            "category": category,
            "level": level.rawValue,
            "kind": kind,
            "message": message,
            "process": Self.processName,
            "pid": Self.pid,
            "id": effectiveNode as Any? ?? NSNull(),
            "parent_id": effectiveParent as Any? ?? NSNull(),
            "root_id": effectiveRoot as Any? ?? NSNull(),
            "payload": payload.dict,
            "parameters": parametersAny,
            "error": error as Any? ?? NSNull()
        ]
        
        guard
            JSONSerialization.isValidJSONObject(record),
            let data = try? JSONSerialization.data(
                withJSONObject: record,
                options: [.withoutEscapingSlashes]
            )
        else {
            return
        }
        
        guard let sink = sinkOverride else { return }
        
        write(data + Data([0x0a]), to: sink)
    }
    
    func appendError(
        _ kind: String,
        _ detail: String,
        category: String,
        rootID: String? = nil
    ) {
        let timestampNanoseconds = Self.nowNs()
        let root = rootID ?? LogContext.rootID
        let header = "=== \(Self.iso(timestampNanoseconds)) \(Self.subsystem):\(kind) "
            + "category=\(category) root=\(root ?? "-")\n"
        let body = detail.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        
        guard let data = (header + body).data(using: .utf8) else { return }
        guard let sink = errorSinkOverride else { return }
        
        write(data, to: sink)
    }
    
    // MARK: - Private
    private static func inferLevel(kind: String) -> LogLevel {
        if kind.hasSuffix(".failed") || kind.hasSuffix(".error") || kind == "rpc.malformed" {
            return .error
        }
        
        if kind.hasSuffix(".skip") || kind.hasSuffix(".skipped") {
            return .warn
        }
        
        if kind.hasSuffix(".ok") || kind.hasSuffix(".completed") || kind.hasSuffix(".applied") {
            return .default
        }
        
        if kind.hasSuffix(".start") || kind.hasSuffix(".started") {
            return .info
        }
        
        return .info
    }
    
    private static func iso(_ timestampNanoseconds: Int64) -> String {
        let seconds = TimeInterval(timestampNanoseconds) / 1_000_000_000
        
        return _isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }
    
    private static func nowNs() -> Int64 {
        let now = Date().timeIntervalSince1970
        
        return Int64(now * 1_000_000_000)
    }
    
    fileprivate static func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        
        case .bool(let bool):
            return bool
        
        case .int(let integer):
            return integer
        
        case .double(let double):
            return double
        
        case .string(let string):
            return string
        
        case .array(let array):
            return array.map(jsonValueToAny)
        
        case .object(let object):
            return object.mapValues(jsonValueToAny)
        }
    }
    
    private func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            rotateIfNeeded(url, incoming: data.count)
            
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url)
            }
        } catch {
        }
    }
    
    private func rotateIfNeeded(_ url: URL, incoming: Int) {
        guard maxBytes > 0 else { return }
        
        let fileManager = FileManager.default
        
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.intValue
        else {
            return
        }
        
        guard size + incoming > maxBytes else { return }
        
        let rotated = url.appendingPathExtension("1")
        
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: url, to: rotated)
    }
}
