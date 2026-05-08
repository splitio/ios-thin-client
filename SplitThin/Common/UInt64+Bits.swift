//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation

extension UInt64 {
    private static let kSize: UInt64 = 64

    func rotateLeft(_ pos: UInt64) -> UInt64 {
        let move = pos % UInt64.kSize
        return (self << move) | (self >> (UInt64.kSize - move))
    }
}
