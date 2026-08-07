//
//  OpenAIBackend.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct OpenAICompatibleBackend: ChatTransport {
    // MARK: - Property
    let baseURL: URL
    let apiKey: String?
    
    private let session: URLSession
    
    // MARK: - Initializer
    init(baseURL: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - Public
    static func requestBody(
        model: String?,
        messages: [ChatMessage],
        tools: [ToolSpec],
        jsonMode: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "messages": messages.map(serializeMessage),
            "stream": false,
            "temperature": 0
        ]
        
        if let model { body["model"] = model }
        
        if !tools.isEmpty {
            body["tools"] = tools.map(serializeTool)
        }
        
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        
        return body
    }
    
    static func serializeMessage(_ message: ChatMessage) -> [String: Any] {
        var object: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content
        ]
        
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = message.toolCalls.map { toolCall -> [String: Any] in
                [
                    "id": toolCall.id,
                    "type": "function",
                    "function": [
                        "name": toolCall.name,
                        "arguments": toolCall.arguments
                    ]
                ]
            }
        }
        
        if let toolCallIdentifier = message.toolCallID {
            object["tool_call_id"] = toolCallIdentifier
        }
        
        return object
    }
    
    static func serializeTool(_ tool: ToolSpec) -> [String: Any] {
        let parameters = tool.parametersJSON.data(using: .utf8)
            .flatMap { data in try? JSONSerialization.jsonObject(with: data) } ?? [:]
        
        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": parameters
            ]
        ]
    }
    
    static func parse(_ data: Data) throws -> ChatCompletion {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MalformedOutput("openai-compat: response is not a JSON object")
        }
        
        guard
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            throw MalformedOutput("openai-compat: missing choices[0].message")
        }
        
        let content = message["content"] as? String ?? ""
        let toolCalls = try parseToolCalls(message["tool_calls"])
        
        if content.isEmpty && toolCalls.isEmpty {
            throw MalformedOutput(
                "openai-compat: choices[0].message has neither content nor tool_calls"
            )
        }
        
        let finishReason = ChatFinishReason(rawValue: first["finish_reason"] as? String)
        var usage: [String: Int]?
        
        if let rawUsage = object["usage"] as? [String: Any] {
            let integerUsage = rawUsage.compactMapValues { value -> Int? in
                if let integer = value as? Int { return integer }
                if let number = value as? NSNumber { return number.intValue }
                
                return nil
            }
            
            usage = integerUsage.isEmpty ? nil : integerUsage
        }
        
        return ChatCompletion(
            text: content,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: usage
        )
    }
    
    static func parseToolCalls(_ value: Any?) throws -> [ChatToolCall] {
        guard let value, !(value is NSNull) else { return [] }
        
        guard let objects = value as? [[String: Any]] else {
            throw MalformedOutput("openai-compat: message.tool_calls is not an array of objects")
        }
        
        var toolCalls: [ChatToolCall] = []
        
        for (index, object) in objects.enumerated() {
            guard
                let function = object["function"] as? [String: Any],
                let name = function["name"] as? String
            else {
                throw MalformedOutput(
                    "openai-compat: message.tool_calls[\(index)] lacks function/name"
                        + " — rejecting the whole response (no partial tool execution)"
                )
            }
            
            let identifier = (object["id"] as? String) ?? "call_\(index)"
            let arguments: String
            
            if let string = function["arguments"] as? String {
                arguments = string
            } else if let rawArguments = function["arguments"] {
                arguments = (try? JSONSerialization.data(withJSONObject: rawArguments))
                    .flatMap { data in String(data: data, encoding: .utf8) } ?? "{}"
            } else {
                arguments = "{}"
            }
            
            toolCalls.append(ChatToolCall(id: identifier, name: name, arguments: arguments))
        }
        
        return toolCalls
    }
    
    static func translate(_ error: URLError) -> any ForgeError {
        switch error.code {
        case .timedOut:
            return BackendTimeout("openai-compat: request timed out")
        
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
            .networkConnectionLost, .notConnectedToInternet:
            return BackendUnavailable(
                "openai-compat: unreachable (\(error.errorCode)) — \(error.localizedDescription)"
            )
        
        default:
            return BackendNonzeroExit(
                "openai-compat: URLError \(error.errorCode) — \(error.localizedDescription)",
                exitCode: Int32(error.errorCode)
            )
        }
    }
    
    static func httpError(status: Int, body: Data) -> any ForgeError {
        let text = String(data: body, encoding: .utf8) ?? ""
        let snippet = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        
        if status >= 500 {
            return BackendUnavailable("openai-compat HTTP \(status): \(snippet)")
        }
        
        return BackendNonzeroExit(
            "openai-compat HTTP \(status): \(snippet)",
            exitCode: Int32(status)
        )
    }
    
    func complete(
        messages: [ChatMessage],
        tools: [ToolSpec],
        model: String?,
        jsonMode: Bool
    ) async throws -> ChatCompletion {
        let body = Self.requestBody(
            model: model,
            messages: messages,
            tools: tools,
            jsonMode: jsonMode
        )
        
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled || Task.isCancelled { throw CancellationError() }
            
            throw Self.translate(urlError)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MalformedOutput("openai-compat: non-HTTP response")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.httpError(status: httpResponse.statusCode, body: data)
        }
        
        return try Self.parse(data)
    }
    
    // MARK: - Private
}
