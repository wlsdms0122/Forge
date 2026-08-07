//
//  TemplateSegment.swift
//  Spec
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public enum TemplateSegment: Sendable, Equatable {
    case text(String)
    case ref(path: [PathSegment])
}
