//
//  Duration+Milliseconds.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

extension Duration {
    var milliseconds: Int {
        let components = components
        
        return Int(
            components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        )
    }
}
