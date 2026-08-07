//
//  StatusMethod.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct DaemonStatusMethod: Sendable {
    // MARK: - Property
    let session: String
    let socketPath: String
    let runtimeDirectory: URL
    let bootedAt: Date
    let configSnapshot: ConfigSnapshot
    let workflowStore: SpecCatalog
    let scheduleStore: ScheduleStore
    let jobStore: JobStore
    let supervisor: ServiceSupervisor
    let handlerBus: WorkflowHandlerBus
    
    // MARK: - Initializer
    // MARK: - Public
    func handle(_ request: RPCRequest) async throws -> JSONObject {
        var config = await configSnapshot.current().asJSONDict()
        
        if var values = config["values"] as? [[String: Any]] {
            values.append(["key": "socket", "value": socketPath, "source": "session"])
            values.append(["key": "runtime_directory", "value": runtimeDirectory.path, "source": "session"])
            config["values"] = values
        }
        
        let schedules = await scheduleStore.all()
        let services = await supervisor.statuses()
        let registered = Set(await handlerBus.listing().map(\.0))
        let workflowCount = await workflowStore.catalog().entries.count
        let jobCount = await jobStore.all().count
        
        let daemon: [String: Any] = [
            "session": session,
            "socket": socketPath,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "started_at": ISO8601.string(bootedAt),
            "uptime_s": Int(Date().timeIntervalSince(bootedAt))
        ]
        
        let runtime: [String: Any] = [
            "workflows": workflowCount,
            "schedules": [
                "total": schedules.count,
                "enabled": schedules.filter { schedule in schedule.enabled }.count
            ],
            "jobs": jobCount,
            "services": services.map { record -> [String: Any] in
                var dictionary = record.dict
                dictionary["registered"] = registered.contains(record.name)
                
                return dictionary
            }
        ]
        
        return [
            "daemon": daemon,
            "config": config,
            "runtime": runtime
        ]
    }
    
    // MARK: - Private
}
