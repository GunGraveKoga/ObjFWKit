//
//  OFUDPSocket.swift
//  ObjFWKitTests
//
//  Created by Юрий Вовк on 23.05.2018.
//

import XCTest
import ObjFWKit

class OFUDPSocketTests: XCTestCase {
    private var _socket: OFUDPSocket?
    private var _port1: UInt16 = 0
    
    open func socketTest() {
        _socket = OFUDPSocket()
        
        XCTAssertNotNil(_socket)
    }
    
    open func bindTest() {
        XCTAssertNotNil(_socket)
        
        do {
            _port1 = try _socket?.bindToHost("127.0.0.1") ?? 0
        } catch {
            XCTAssert(false, "Error: \(error)")
        }
        
        XCTAssert(_port1 != 0)
    }
    
    
    
    static let allTests = [
        ("socketTest", socketTest),
        ("bindTest", bindTest),
    ]
}
