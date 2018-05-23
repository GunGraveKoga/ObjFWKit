//
//  MD5Hash.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 22.05.2018.
//

import Foundation

public struct MD5Hash: OFCryptoHash {
    
    public var digestSize: Int = 16
    
    public var blockSize: Int = 64
    
    private var _isCalculated: Bool = false
    
    public var calculated: Bool {
        get {
            return _isCalculated
        }
    }
    
    public var digest: UnsafePointer<CChar>!
    
    public func update(withBuffer buffer: UnsafeMutableRawPointer, length: Int) {
        <#code#>
    }
    
    public func reset() {
        <#code#>
    }
    
    
}
