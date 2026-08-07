//
//  ScheduleCreateCommand.swift
//  ForgeCLI
//
//  Created by JSilver on 8/9/26.
//

import ArgumentParser
import Foundation

struct ScheduleCreateCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a schedule (runtime dir).",
        discussion: """
            Registers a schedule in the runtime dir (runtime_directory/schedule).
            Fires either a registered workflow (`--workflow <name>`) or an
            anonymous inline workflow (`--spec <json>`) on a trigger —
            exactly one of:

                --every <dur>            repeat forever, every interval
                --at <HH:mm> --timezone  repeat on a wall-clock (combine --days)
                --once <ts> --timezone   fire once at 'yyyy-MM-dd HH:mm:ss'
                --after <dur>            fire once, this much from now

            `--once`/`--after` are one-shot fires.
            A one-shot stays on disk after firing — runtime-created ones are
            auto-GC'd by the daemon; hand-authored config ones show `spent` in
            `list` for you to remove. The target flags are mutually exclusive;
            inline `spec` rejects a `name` key and runs gated by the `<inline>`
            sigil — identical shape to `workflow dispatch --spec`.

            Creation is policy-gated: your principal must be allowed to
            dispatch the target workflow directly (policy/*.yaml), or the
            registration is refused.

            Remove with `forge schedule delete <id>`.

            Example values (`<wf>`, channel IDs, JSON contents) are
            placeholders — substitute your own.

            EXAMPLE — registered workflow, repeating:
                forge schedule create --workflow <wf> \\
                    --every 1h --inputs '{"channel":"<channel-id>"}'

            EXAMPLE — inline spec, one-shot in 30 minutes:
                forge schedule create --after 30m --spec '{
                  "steps": [{"id":"send","shell":{"command":["forge","service","send","slack",
                    "--payload","{\\"kind\\":\\"slack.thread\\",\\"target\\":\\"<permalink>\\",\\"text\\":\\"<message>\\"}"]}}]
                }'
            """
    )
    
    @OptionGroup var global: GlobalOptions
    
    @Option(help: "Registered workflow name. Omit when using --spec.")
    var workflow: String?
    
    @Option(help: "Inline anonymous workflow JSON — use instead of --workflow.")
    var spec: String?
    
    @Option(help: "Repeat every interval (30s 5m 1h 2d).")
    var every: String?
    
    @Option(help: "Repeat at wall-clock 'HH:mm' (24h). Requires --timezone; combine with --days.")
    var at: String?
    
    @Option(help: "Weekdays for --at, comma-separated (mon,tue,wed,thu,fri,sat,sun). Omit for every day.")
    var days: String?
    
    @Option(help: "Fire once at wall-clock 'yyyy-MM-dd HH:mm:ss'. Requires --timezone.")
    var once: String?
    
    @Option(help: "Fire once, this much from now (30s 5m 1h 2d).")
    var after: String?
    
    @Option(help: "IANA timezone (e.g. Asia/Seoul). Required with --at / --once; rejected otherwise.")
    var timezone: String?
    
    @Option(help: "Schedule id (default: auto-generated).")
    var id: String?
    
    @Option(help: "Workflow inputs as a JSON object.")
    var inputs: String?
    
    @Option(help: "Concurrency policy: queue | skip | replace.")
    var concurrency: String?
    
    @Flag(help: "Emit JSON.")
    var json: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let socketPath = try resolveSocket(global)
        let token = resolveToken(global.token)
        
        var params: [String: Any] = [:]
        
        if let every { params["every"] = every }
        if let at { params["at"] = at }
        if let once { params["once"] = once }
        if let after { params["after"] = after }
        if let timezone { params["timezone"] = timezone }
        
        if let days {
            params["days"] = days
                .split(separator: ",")
                .map { day in day.trimmingCharacters(in: .whitespaces) }
                .filter { day in !day.isEmpty }
        }
        
        if let workflow { params["workflow"] = workflow }
        if let spec { params["spec"] = parseJSONObjectArg(spec, flag: "--spec") }
        if let id { params["id"] = id }
        if let inputs { params["inputs"] = parseJSONObjectArg(inputs, flag: "--inputs") }
        if let concurrency { params["concurrency"] = concurrency }
        
        switch callRPC(
            socketPath: socketPath,
            method: "schedule.create",
            params: params,
            token: token
        ) {
        case .ok(let dict):
            if json { printJSON(dict) } else { print(renderResultPlain(dict)) }
        
        case .err(let type, let message):
            dieRPC("schedule create", type: type, message: message)
        }
    }
    
    // MARK: - Private
}
