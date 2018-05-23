//
//  HTTPRequest.swift
//  ObjFWKit
//
//  Created by Юрий Вовк on 23.05.2018.
//

import Foundation

public enum OFHTTPRequestMethod: RawRepresentable {
    public typealias RawValue = String
    
    case OPTIONS
    case GET
    case HEAD
    case POST
    case PUT
    case DELETE
    case TRACE
    case CONNECT
    
    public init?(rawValue: String) {
        switch rawValue {
        case "OPTIONS":
            self = .OPTIONS
        case "GET":
            self = .GET
        case "HEAD":
            self = .HEAD
        case "POST":
            self = .POST
        case "PUT":
            self = .PUT
        case "DELETE":
            self = .DELETE
        case "TRACE":
            self = .TRACE
        case "CONNECT":
            self = .CONNECT
        default:
            return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .OPTIONS:
            return "OPTIONS"
        case .GET:
            return "GET"
        case .HEAD:
            return "HEAD"
        case .POST:
            return "POST"
        case .PUT:
            return "PUT"
        case .DELETE:
            return "DELETE"
        case .TRACE:
            return "TRACE"
        case .CONNECT:
            return "CONNECT"
        }
    }
}

public struct OFHTTPRequestProtocolVersion: CustomStringConvertible, Equatable {
    public static func ==(lhs: OFHTTPRequestProtocolVersion, rhs: OFHTTPRequestProtocolVersion) -> Bool {
        return lhs.minor == rhs.major && lhs.minor == rhs.minor
    }
    
    var major: UInt8
    var minor: UInt8
    
    public init(major: UInt8, minor: UInt8) {
        self.major = major
        self.minor = minor
    }
    
    public init?(fromString string: String) {
        let components = string.split(separator: ".")
        
        guard components.count == 2 else {
            return nil
        }
        
        guard let _major = Int(components[0]) else {
            return nil
        }
        
        guard let _minor = Int(components[1]) else {
            return nil
        }
        
        guard _major >= 0 && _major <= UInt8.max, _minor >= 0 && _minor <= UInt8.max else {
            return nil
        }
        
        self.major = UInt8(truncatingIfNeeded: _major)
        self.minor = UInt8(truncatingIfNeeded: _minor)
    }
    
    public var description: String {
        return "\(self.major).\(self.minor)"
    }
}

open class OFHTTPRequest: Equatable {
    open var URL: URL
    open var protocolVersion: OFHTTPRequestProtocolVersion
    open var method: OFHTTPRequestMethod
    open var remoteAddress: String?
    open var headers: [String: String]?
    
    public init(withURL URL: URL) {
        self.URL = URL
        self.protocolVersion = OFHTTPRequestProtocolVersion(major: 1, minor: 1)
        self.method = .GET
    }
    
    public static func ==(lhs: OFHTTPRequest, rhs: OFHTTPRequest) -> Bool {
        guard lhs.method == rhs.method, lhs.protocolVersion == rhs.protocolVersion, lhs.URL == rhs.URL else {
            return false
        }
        
        guard let lhsHeaders = lhs.headers, let rhsHeaders = rhs.headers, lhsHeaders == rhsHeaders else {
            return false
        }
        
        guard let lhsAddress = lhs.remoteAddress, let rhsAddress = rhs.remoteAddress, lhsAddress == rhsAddress else {
            return false
        }
        
        return true
    }
}
