//
//  AgentActionForm.swift
//  Forge
//
//  Created by JSilver on 8/16/26.
//

import Foundation
import Warp
import WarpIR

struct AgentActionForm: WarpIR.ConstructForm {
    // MARK: - Property
    static let key = "agent"

    private let prompt: Warp.Expression

    // MARK: - Initializer
    init(from decoder: Decoder) throws {
        self.prompt = try ExpressionReader(from: decoder).expression
    }

    // MARK: - Public
    func expression(boundTo id: String) -> Warp.Expression {
        .dispatch(Dispatch(selector: ForgeSpec.selector(Self.key), arguments: ["prompt": prompt]))
    }

    // MARK: - Private
}
