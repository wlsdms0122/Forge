//
//  FileHandle+Line.swift
//  ForgeCLI
//
//  Created by JSilver on 10/25/26.
//

import Foundation

extension FileHandle {
    func write(line text: String) {
        write(Data((text + "\n").utf8))
    }
}
