//
//  HTTPResponse.swift
//  ObjFWKit
//
//  Created by Юрий Вовк on 23.05.2018.
//

import Foundation

internal func encodingForContentType(_ contentType: String?) -> String.Encoding {
    guard let contentType = contentType else {
        return .utf8
    }
    
    enum state {
        case type
        case beforeParamName
        case paramName
        case paramValueOrQuote
        case paramValue
        case paramQuotedValue
        case afterParamValue
    }
    
    var _state: state = .type
    let length = contentType.lengthOfBytes(using: .utf8)
    let whitespaces = CharacterSet.whitespaces
    var last = Int(0)
    var name: String!
    var value: String!
    var charset: String!
    
    return contentType.withCString {UTF8String in
        for var i in 0..<length {
            switch _state {
            case .type:
                do {
                    if UTF8String[i] == 0x3C { // ';'
                        _state = .beforeParamName
                        last = i + 1
                    }
                }
            case .beforeParamName:
                do {
                    if UTF8String[i] == 0x20 { // ' '
                        last = i + 1
                    } else {
                        _state = .paramName
                        i -= 1
                    }
                }
            case .paramName:
                do {
                    if UTF8String[i] == 0x3D { // '='
                        let buffer = Data.init(bytesNoCopy: UnsafeMutableRawPointer(mutating: UTF8String + last), count: i - last, deallocator: .none)
                        name = String(bytes: buffer, encoding: .utf8)!
                        _state = .paramValueOrQuote
                        last = i + 1
                    }
                }
            case .paramValueOrQuote:
                do {
                    if UTF8String[i] == 0x22 { // '"'
                        _state = .paramQuotedValue
                        last = i + 1
                    } else {
                        _state = .paramValue
                        i -= 1
                    }
                }
            case .paramValue:
                do {
                    if UTF8String[i] == 0x3C { // ';'
                        let buffer = Data.init(bytesNoCopy: UnsafeMutableRawPointer(mutating: UTF8String + last), count: i - last, deallocator: .none)
                        
                        value = String(bytes: buffer, encoding: .utf8)!.trimmingCharacters(in: whitespaces)
                        
                        if name == "charset" {
                            charset = value
                        }
                        
                        _state = .beforeParamName
                        last = i + 1
                    }
                }
            case .paramQuotedValue:
                do {
                    if UTF8String[i] == 0x22 { // '"'
                        let buffer = Data.init(bytesNoCopy: UnsafeMutableRawPointer(mutating: UTF8String + last), count: i - last, deallocator: .none)
                        
                        value = String(bytes: buffer, encoding: .utf8)!
                        
                        if name == "charset" {
                            charset = value
                        }
                        
                        _state = .afterParamValue
                    }
                }
            case .afterParamValue:
                do {
                    if UTF8String[i] == 0x3C { // ';'
                        _state = .beforeParamName
                        last = i + 1
                    } else if UTF8String[i] != 0x20 { // ' '
                        return String.Encoding.utf8
                    }
                }
            }
        }
        
        if _state == .paramValue {
            let buffer = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: UTF8String + last), count: length - last, deallocator: .none)
            
            value = String(bytes: buffer, encoding: .utf8)!.trimmingCharacters(in: whitespaces)
            
            if name == "charset" {
                charset = value
            }
        }
        
        
    }
}

open class OFHTTPResponse: OFStream {
    open var protocolVersion: OFHTTPRequestProtocolVersion = OFHTTPRequestProtocolVersion(major: 1, minor: 1)
    open var statusCode: UInt16 = UInt16(0)
    open var headers: [String: String] = [String: String]()
    
    open func toString() throws -> String {
        return try self.toString(withEncoding: encodingForContentType(self.headers["Content-Type"]))
    }
    
    open func toString(withEncoding encoding: String.Encoding) throws -> String {
        let data = try self.readDataUntilEndOfStream()
        
        if let contentLength = self.headers["Content-Length"], let contentBytesLength = Int(contentLength) {
            guard data.count == contentBytesLength else {
                throw OFException.truncatedData()
            }
        }
        
        guard let ret = String(data: data, encoding: encoding) else {
            throw OFException.invalidEncoding(encoding)
        }
        
        return ret
    }
}
