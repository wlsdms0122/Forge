//
//  TimeZone+Testing.swift
//  ForgeTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

extension TimeZone {
    /// The reference time zone for schedule tests. Passing the identifier as a loose string lets a typo silently become UTC.
    static let seoul = TimeZone(identifier: "Asia/Seoul")!
}
