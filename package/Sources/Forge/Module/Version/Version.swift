//
//  Version.swift
//  Forge
//
//  Created by JSilver on 8/11/26.
//

import Foundation

// The single place the product version is written. The CLI's `--version`,
// the daemon's status report, and runtime.json all read this constant —
// bump it as part of cutting a release tag.
public enum Version {
    public static let current = "0.1.0"
}
