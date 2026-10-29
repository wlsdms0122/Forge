//
//  Trait+ExclusiveResource.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Testing

extension Trait where Self == ExclusiveResource {
    static func exclusive(_ resource: ExclusiveResource.Name) -> Self {
        ExclusiveResource(name: resource.rawValue)
    }
}
