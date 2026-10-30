//
//  Item.swift
//  Stock Chat
//
//  Created by Fei HH on 2026/10/30.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
