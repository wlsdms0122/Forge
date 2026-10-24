//
//  DaemonStatusMethod.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct DaemonStatusMethod: Sendable {
    // MARK: - Property
    let instance: String
    let socketPath: String
    let runtimeDirectory: URL
    let bootedAt: Date
    let configSnapshot: ConfigSnapshot
    let catalog: WorkflowCatalog
    let scheduleStore: ScheduleStore
    let jobStore: JobStore
    let supervisor: ServiceSupervisor
    let handlerBus: WorkflowHandlerBus
    
    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONValue {
        var config = await configSnapshot.current().fields
        
        if var values = config["values"]?.arrayValue {
            values.append(["key": "socket", "value": .string(socketPath), "source": "instance"])
            values.append(["key": "runtime_directory", "value": .string(runtimeDirectory.path), "source": "instance"])
            config["values"] = .array(values)
        }
        
        let schedules = await scheduleStore.all()
        let services = await supervisor.statuses()
        let registered = Set(await handlerBus.listing().map(\.0))
        let workflowCount = await catalog.reload().entries.count
        let jobCount = await jobStore.all().count
        
        let daemon: JSONValue = [
            "instance": .string(instance),
            "version": .string(Version.current),
            "socket": .string(socketPath),
            "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
            "started_at": .string(ISO8601.string(bootedAt)),
            "uptime_s": .int(Int(Date().timeIntervalSince(bootedAt)))
        ]
        
        let runtime: JSONValue = [
            "workflows": .int(workflowCount),
            "schedules": [
                "total": .int(schedules.count),
                "enabled": .int(schedules.filter { schedule in schedule.enabled }.count)
            ],
            "jobs": .int(jobCount),
            "services": .array(services.map { record in
                var object = record.fields
                object["registered"] = .bool(registered.contains(record.name))
                
                return .object(object)
            })
        ]
        
        return [
            "daemon": daemon,
            "config": .object(config),
            "runtime": runtime
        ]
    }
    
    // MARK: - Private
}
