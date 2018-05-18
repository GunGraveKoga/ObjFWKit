//
//  StdIO.swift
//  StreamsKit
//
//  Created by Yury Vovk on 10.05.2018.
//

import Foundation

public class StdIOStream: StreamsKit.Stream {
    internal var _fd: Int32 = -1
    internal var _atEndOFStream: Bool = false
    #if os(Windows)
    private static let _stdin = StdIOStream_Win32Console(withFileDescriptor: 0)
    private static let _stdout = StdIOStream_Win32Console(withFileDescriptor: 1)
    private static let _stderr = StdIOStream_Win32Console(withFileDescriptor: 2)
    #else
    private static let _stdin = StdIOStream(withFileDescriptor: 0)
    private static let _stdout = StdIOStream(withFileDescriptor: 1)
    private static let _stderr = StdIOStream(withFileDescriptor: 2)
    #endif
    
    public class var stdin: StdIOStream {
        get {
            return _stdin
        }
    }
    
    public class var stdout: StdIOStream {
        get {
            return _stdout
        }
    }
    
    public class var stderr: StdIOStream {
        get {
            return _stderr
        }
    }
    
    public var columns: Int {
        get {
            #if !os(Windows)
                var ws = winsize()
                
                guard ioctl(_fd, TIOCGWINSZ, UnsafeMutablePointer(&ws)) == 0 else {
                    return -1
                }
                
                return Int(ws.ws_col)
            #else
                return -1
            #endif
        }
    }
    
    public var rows: Int {
        get {
            #if !os(Windows)
                var ws = winsize()
                
                guard ioctl(_fd, TIOCGWINSZ, UnsafeMutablePointer(&ws)) == 0 else {
                    return -1
                }
                
                return Int(ws.ws_row)
            #else
                return -1
            #endif
        }
    }
    
    public override func lowLevelIsAtEndOfStream() throws -> Bool {
        guard _fd != -1 else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        return _atEndOFStream
    }
    
    public override func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        guard _fd != -1 else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        var ret: Int
        
        #if os(Windows)
            guard length <= UInt32.max else {
                throw StreamsKitError.outOfRange
            }
            
            ret = MinGWCrt.read(_fd, buffer, UInt32(length))
        #elseif os(Linux)
            ret = Glibc.read(_fd, buffer, length)
        #else
            ret = Darwin.read(_fd, buffer, length)
        #endif
        
        guard ret >= 0 else {
            throw StreamsKitError.readFailed(stream: self, requestedLength: length, error: errno)
        }
        
        return ret
    }
    
    public override func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        guard _fd != -1 else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        var bytesWritten: Int
        
        #if os(Windows)
            guard length <= Int32.max else {
                throw StreamsKitError.outOfRange
            }
            
            let _bytesWritten = MinGWCrt.write(_fd, buffer, Int32(length))
        #elseif os(Linux)
            bytesWritten = Glibc.write(_fd, buffer, length)
        #else
            bytesWritten = Darwin.write(_fd, buffer, length)
        #endif
        
        guard bytesWritten >= 0 else {
            throw StreamsKitError.writeFailed(stream: self, requestedLength: length, bytesWritten: 0, error: errno)
        }
        
        return bytesWritten
    }
    
    internal init(withFileDescriptor fileDescriptor: Int32) {
        _fd = fileDescriptor
    }
    
    deinit {
        try! self.close()
    }
    
    public override func close() throws {
        if _fd != -1 {
            #if os(Windows)
            MinGWCrt.close(_fd)
            #elseif os(Linux)
            Glibc.close(_fd)
            #else
            Darwin.close(_fd)
            #endif
        }
        
        try super.close()
    }
}

#if os(Windows)
    
import CWin32

fileprivate final class StdIOStream_Win32Console: StdIOStream {
    internal var _handle: HANDLE!
    internal var _regularStdIOStream: Bool = false
    
    internal override init(withFileDescriptor fileDescriptor: Int32) {
        super.init(withFileDescriptor: fileDescriptor)
        
        var mode: DWORD = 0
        
        switch fileDescriptor {
        case 0:
            _handle = GetStdHandle(DWORD(bitPattern: -10))
        case 1:
            _handle = GetStdHandle(DWORD(bitPattern: -11))
        case 2:
            _handle = GetStdHandle(DWORD(bitPattern: -12))
        default:
            fatalError("Invalid argument \(fileDescriptor)")
        }
        
        let res = GetConsoleMode(_handle, UnsafeMutablePointer(&mode))
        
        if res == 0 {
            _regularStdIOStream = true
        }
    }
    
    override func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        if _regularStdIOStream {
            return try super.lowLevelRead(into: &buffer, length: length)
        }
        
        guard length <= UInt32.max else {
            throw StreamsKitError.outOfRange
        }
        
        var UTF16 = UnsafeMutablePointer<UTF16Char>.allocate(capacity: length)
        UTF16.initialize(to: 0)
        
        var UTF16Len: DWORD = 0
        
        defer {
            UTF16.deallocate(capacity: length * 2)
        }
        
        guard ReadConsoleW(_handle, UTF16, DWORD(length), UnsafeMutablePointer(&UTF16Len), nil) != 0 else {
            throw StreamsKitError.readFailed(stream: self, requestedLength: length * 2, errNo: EIO)
        }
        
        if UTF16Len > 0 {
            let str = String(utf16CodeUnitsNoCopy: UTF16, count: Int(UTF16Len), freeWhenDone: false)
            
            str.withCString {
                buffer.copyBytes(from: $0, count: strlen($0))
            }
        }
        
        if UTF16Len == 0 {
            _atEndOFStream = true
        }
        
        return Int(UTF16Len) * 2
    }
    
    override func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        if _regularStdIOStream {
            return try super.lowLevelWrite(buffer, length: length)
        }
        
        let str = String(utf8String: buffer.assumingMemoryBound(to: Int8.self))!
        
        var _bytesWritten: DWORD = 0
        var rc: WINBOOL = 0
        
        str.withCString(encodedAs: UTF16.self) {
            rc = WriteConsoleW(_handle, $0, DWORD(str.count), UnsafeMutablePointer(&_bytesWritten), nil)
        }
        
        guard rc == 1 else {
            throw StreamsKitError.writeFailed(stream: self, requestedLength: str.count, bytesWritten: 0, errNo: EIO)
        }
        
        let bytesWritten = Int(_bytesWritten)
        
        guard bytesWritten == str.count else {
            throw StreamsKitError.writeFailed(stream: self, requestedLength: str.count * 2, bytesWritten: bytesWritten * 2, errNo: 0)
        }
        
        return bytesWritten * 2
    }
}

#endif
