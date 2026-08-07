//
//  WorkflowDispatchCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct WorkflowDispatchCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "dispatch",
        abstract: "Dispatch a workflow run.",
        discussion: """
            Runs a registered workflow by name, or an anonymous inline
            workflow by `--spec` (JSON; a `name` key is rejected — the run is
            named `<inline>` and gated by that sigil).

            IDENTITY & ENVELOPE
                The bearer token (FORGE_ACCESS_TOKEN or --token) carries the
                caller's identity. A workflow subprocess's injected token is
                a cli:<workflow> token — root / correlator / parameters /
                origin are then inherited from the parent run server-side
                and the corresponding flags are ignored (a nested run cannot
                forge its own coordinates). An operator token (system:*)
                carries no parent, so --parameters / --correlator / --origin
                / --root-id / --parent-id apply.

            BLOCKING vs --async vs --stream
                `dispatch` blocks until the workflow completes and returns
                the full result. Pass --async to return as soon as the run
                is dispatched: { workflow_id, name, status: "running" } —
                fire-and-forget; the run continues in the background and is
                observable in the forge log.

                Pass --stream to keep the connection open and print the
                run's progress as JSONL, one object per line:
                  { "kind": "workflow.event", "event": "step.started", ... }
                  ...
                  { "kind": "workflow.result", "result": {...final result...} }
                Child workflows dispatched by the run share its root and
                stream too. Disconnecting does NOT cancel the run (use
                `workflow cancel`). --stream implies JSON output and is
                mutually exclusive with --async.

            Example values (`<wf>`, JSON contents, etc.) are placeholders —
            substitute names registered in your own forge home.

            EXAMPLE
                forge workflow dispatch <wf> \\
                    --inputs '{"user_input":"..."}'

                forge workflow dispatch <wf> --async \\
                    --inputs '{"channel":"<channel-id>"}'
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Argument(help: "Registered workflow name. Omit when using --spec.")
    var name: String?
    
    @Option(help: "Inline anonymous workflow JSON — use instead of the name argument.")
    var spec: String?
    
    @Option(help: "Workflow inputs as a JSON object (default: {}).")
    var inputs: String?
    
    @Option(help: "Caller passthrough as a JSON object — rides the log envelope only.")
    var parameters: String?
    
    @Option(help: "Opaque correlator string — ridden through to handler frames.")
    var correlator: String?
    
    @Option(help: "Trigger as JSON, e.g. {\"kind\":\"manual\",\"id\":\"...\"}.")
    var origin: String?
    
    @Option(name: .customLong("root-id"), help: "Parent root id (node tree root) to inherit.")
    var rootID: String?
    
    @Option(name: .customLong("parent-id"), help: "Parent node id to attach under.")
    var parentNodeID: String?
    
    @Flag(
        name: .customLong("async"),
        help: "Return as soon as the run is dispatched, without blocking for the result."
    )
    var isAsync: Bool = false
    
    @Flag(help: "Stream the run's progress as JSONL (workflow.event lines, then a workflow.result line).")
    var stream: Bool = false
    
    @Flag(help: "Emit the full RPC response as JSON (default: readable result).")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        
        guard (name != nil) != (spec != nil) else {
            die("workflow dispatch: pass exactly one of a workflow name argument or --spec", code: 4)
        }
        
        var params: [String: Any] = ["async": isAsync]
        
        if let name { params["name"] = name }
        if let spec { params["spec"] = parseJSONObjectArg(spec, flag: "--spec") }
        
        params["inputs"] = inputs
            .map { value in parseJSONObjectArg(value, flag: "--inputs") } ?? [:]
        
        if let parameters {
            params["parameters"] = parseJSONObjectArg(parameters, flag: "--parameters")
        }
        
        if let correlator { params["correlator"] = correlator }
        
        if let origin {
            params["origin"] = parseJSONObjectArg(origin, flag: "--origin")
        }
        
        if rootID != nil || parentNodeID != nil {
            var root: [String: Any] = [:]
            
            if let rootID { root["root_id"] = rootID }
            if let parentNodeID { root["parent_id"] = parentNodeID }
            
            params["root"] = root
        }
        
        let token = resolveToken(global.token)
        
        if stream {
            guard !isAsync else {
                die("workflow dispatch: --stream and --async are mutually exclusive", code: 4)
            }
            
            runStream(socketPath: socketPath, params: params, token: token)
        }
        
        switch callRPC(
            socketPath: socketPath,
            method: "workflow.dispatch",
            params: params,
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
            
            ForgeCommand.exit()
        
        case .err(let type, let message):
            dieRPC("workflow dispatch", type: type, message: message)
        }
    }
    
    // MARK: - Private
    private func runStream(
        socketPath: String,
        params: [String: Any],
        token: String
    ) -> Never {
        var streamParams = params
        streamParams["token"] = token
        streamParams.removeValue(forKey: "async")
        
        guard let requestData = RPC.requestLine(
            method: "workflow.dispatch_stream",
            params: streamParams
        ) else {
            die("workflow dispatch: encode request failed", code: 4)
        }
        
        guard let socket = StreamSocket(path: socketPath) else {
            die("workflow dispatch: connect failed (socket=\(socketPath))", code: 5)
        }
        
        defer { socket.close() }
        
        guard socket.writeLine(requestData) else {
            die("workflow dispatch: write failed", code: 5)
        }
        
        guard let ackFrame = socket.readFrame() else {
            die("workflow dispatch: no ack from daemon", code: 5)
        }
        
        if case .err(let type, let message) = RPC.parseFrame(ackFrame) {
            dieRPC("workflow dispatch", type: type, message: message)
        }
        
        emitStdoutLine(String(decoding: ackFrame, as: UTF8.self))
        
        while let frame = socket.readFrame() {
            emitStdoutLine(String(decoding: frame, as: UTF8.self))
            
            if let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                (object["kind"] as? String) == "workflow.result" {
                ForgeCommand.exit()
            }
        }
        
        die("workflow dispatch: stream ended without a workflow.result", code: 5)
    }
}
