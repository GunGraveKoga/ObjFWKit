//
//  Hash.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 22.05.2018.
//

import Foundation

public protocol OFCryptoHash {
    var digestSize: Int {get}
    var blockSize: Int {get}
    var calculated: Bool {get}
    var digest: UnsafePointer<CChar>! {get}
    
    mutating func update(withBuffer buffer: UnsafeMutableRawPointer, length: Int) -> Swift.Void
    mutating func reset() -> Swift.Void
    
}
