//
//  Version.swift
//  Forge
//
//  Created by JSilver on 8/11/26.
//

import Foundation

// The product version. The CLI's `--version`, the daemon's status report and
// runtime.json all read it; `[package] version` in manifest.toml is where it
// is written, and the `PackageVersion` plugin carries it here at build.
public enum Version {
    public static let current = packageVersion
}
