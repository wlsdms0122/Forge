//
//  ForgeError+WarpError.swift
//  Forge
//
//  Created by JSilver on 10/29/26.
//

import Foundation
import Warp

// A Forge error the language also refuses with holds no trace and no place, so
// the language's description of it is its message too.
extension ForgeError where Self: Warp.WarpError {
    var description: String { message }
}
