//
//  FireResolution.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum FireResolution {
    case resolved(Workflow)
    case denied(reason: String, detail: String)
}
