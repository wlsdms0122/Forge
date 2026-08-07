//
//  ConfigSnapshot.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

actor ConfigSnapshot {
    // MARK: - Property
    private var report: ConfigReport
    
    // MARK: - Initializer
    init(_ report: ConfigReport) {
        self.report = report
    }
    
    // MARK: - Public
    func current() -> ConfigReport { report }
    
    func updateServices(from new: ConfigReport) {
        let kept = report.entries.filter { entry in !entry.key.hasPrefix("service.") }
        let fresh = new.entries.filter { entry in entry.key.hasPrefix("service.") }
        report = ConfigReport(tomlPath: report.tomlPath, entries: kept + fresh)
    }
    
    // MARK: - Private
}
