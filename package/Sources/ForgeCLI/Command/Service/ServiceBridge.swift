//
//  ServiceBridge.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Forge

final class ServiceBridge: @unchecked Sendable {
    // MARK: - Property
    private let service: String
    private let socketPath: String
    private let schema: JSONValue?
    private let token: String
    private let lock = NSLock()
    private var sock: StreamSocket?
    private var stopped = false
    
    // MARK: - Initializer
    init(service: String, socketPath: String, schema: JSONValue?, token: String) {
        self.service = service
        self.socketPath = socketPath
        self.schema = schema
        self.token = token
    }
    
    // MARK: - Public
    func run() {
        let reader = Thread { [weak self] in self?.readerLoop() }
        reader.stackSize = 1 << 20
        reader.start()
        
        stdinLoop()
    }
    
    // MARK: - Private
    private func readerLoop() {
        guard let socket = connectRegisterOnce() else {
            FileHandle.standardError.write(line: "forge service: connect/register failed — exiting")
            exit(1)
        }
        
        setSocket(socket)
        
        while !isStopped() {
            guard let frame = socket.readFrame() else { break }
            
            if frame.isEmpty { continue }
            
            if let object = try? JSONDecoder().decode(JSONValue.self, from: frame),
                object["kind"]?.stringValue == "service.message" {
                FileHandle.standardOutput.write(line: String(decoding: frame, as: UTF8.self))
            }
        }
        
        setSocket(nil)
        socket.close()
        
        if isStopped() { return }
        
        FileHandle.standardError.write(line: "forge service: connection lost — exiting")
        exit(1)
    }
    
    private func connectRegisterOnce() -> StreamSocket? {
        guard let socket = StreamSocket(path: socketPath) else { return nil }
        
        var params: [String: JSONValue] = ["service": .string(service), "token": .string(token)]
        
        if let schema { params["schema"] = schema }
        
        guard let data = RPC.requestLine(
            method: "service.register",
            params: params,
            idPrefix: "reg"
        ), socket.writeLine(data) else {
            socket.close()
            
            return nil
        }
        
        guard let ackFrame = socket.readFrame() else {
            socket.close()
            
            return nil
        }
        
        if case .err(let type, let message) = RPC.parseFrame(ackFrame) {
            FileHandle.standardError.write(line: "forge service: register failed: \(type): \(message)")
            socket.close()
            
            return nil
        }
        
        FileHandle.standardError.write(line: "forge service: registered service=\(service)")
        
        return socket
    }
    
    private func stdinLoop() {
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            
            guard let data = line.data(using: .utf8),
                let line = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let object = try? JSONValue(jsonObject: line),
                let messageID = object["message_id"]?.stringValue
            else {
                FileHandle.standardError.write(line: "forge service: bad ack line dropped")
                
                continue
            }
            
            var params: [String: JSONValue] = [
                "service": .string(service),
                "message_id": .string(messageID),
                "token": .string(token)
            ]
            
            if let result = object["result"] { params["result"] = result }
            if let error = object["error"] { params["error"] = error }
            
            guard let requestData = RPC.requestLine(
                method: "service.ack",
                params: params,
                idPrefix: "ack"
            ) else {
                continue
            }
            
            lock.lock()
            
            let socket = sock
            
            lock.unlock()
            
            if socket == nil || !(socket!.writeLine(requestData)) {
                FileHandle.standardError.write(line: "forge service: ack drop — connection closed")
            }
        }
        
        stop()
    }
    
    private func isStopped() -> Bool {
        lock.lock()
        
        defer { lock.unlock() }
        
        return stopped
    }
    
    private func stop() {
        lock.lock()
        
        stopped = true
        
        let socket = sock
        sock = nil
        
        lock.unlock()
        socket?.close()
    }
    
    private func setSocket(_ socket: StreamSocket?) {
        lock.lock()
        sock = socket
        lock.unlock()
    }
}
