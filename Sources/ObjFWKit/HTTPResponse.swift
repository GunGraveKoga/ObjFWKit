//
//  HTTPResponse.swift
//  ObjFWKit
//
//  Created by Юрий Вовк on 23.05.2018.
//

import Foundation

public extension String {
    public static func parseEncoding(_ encodingName: String) throws -> String.Encoding {
        switch encodingName.lowercased() {
        case "utf8",
             "utf-8":
            return String.Encoding.utf8
        case "ascii",
             "us-ascii":
            return String.Encoding.ascii
        case "iso-8859-1",
             "iso_8859-1":
            return String.Encoding.isoLatin1
        case "iso-8859-2",
             "iso_8859-2":
            return String.Encoding.isoLatin2
        case "windows-1250",
             "cp1250",
             "cp-1250",
             "1250":
            return String.Encoding.windowsCP1250
        case "windows-1251",
             "cp1251",
             "cp-1251",
             "1251":
            return String.Encoding.windowsCP1251
        case "windows-1252",
             "cp1252",
             "cp-1252",
             "1252":
            return String.Encoding.windowsCP1252
        case "windows-1253",
             "cp1253",
             "cp-1253",
             "1253":
            return String.Encoding.windowsCP1253
        case "windows-1254",
             "cp1254",
             "cp-1254",
             "1254":
            return String.Encoding.windowsCP1254
        case "macintosh",
             "mac":
            return String.Encoding.macOSRoman
        case "utf61",
             "utf-16":
            return String.Encoding.utf16
        case "utf32",
             "utf-32":
            return String.Encoding.utf32
        default:
            throw OFException.invalidEncoding()
        }
    }
}

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
        
        guard let encoding = try? String.parseEncoding(charset) else {
            return .utf8
        }
        
        return encoding
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
