//
//  PipeReaderError.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum PipeReaderError: ForgeError {
    case creationFailed(errno: Int32)
    
    var message: String {
        switch self {
        case .creationFailed(let code):
            return "failed to create pipe (errno=\(code))"
        }
    }
}
