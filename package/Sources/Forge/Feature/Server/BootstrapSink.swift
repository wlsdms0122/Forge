//
//  BootstrapSink.swift
//  Forge
//
//  Created by JSilver on 8/9/26.
//

import Foundation

enum BootstrapSink: Equatable {
    case fd(Int32)
    case stdout
    case withheld
}
