//
//  File.swift
//  StreamsKit
//
//  Created by Yury Vovk on 08.05.2018.
//

import Foundation

#if os(Windows)
    public let O_CLOEXEC: Int32 = 0
    public let O_EXLOCK: Int32 = 0
#elseif os(macOS)
    public let O_BINARY: Int32 = 0
#endif

fileprivate func parseMode(_ mode: String) -> Int32 {
    switch mode {
    case "r":
        return O_RDONLY
    case "r+":
        return O_RDWR
    case "w":
        return O_WRONLY | O_CREAT | O_TRUNC
    case "wx":
        return O_WRONLY | O_CREAT | O_EXCL | O_EXLOCK
    case "w+":
        return O_RDWR | O_CREAT | O_TRUNC
    case "w+x":
        return O_RDWR | O_CREAT | O_EXCL | O_EXLOCK
    case "a":
        return O_WRONLY | O_CREAT | O_APPEND
    case "a+":
        return O_RDWR | O_CREAT | O_APPEND
    default:
        return -1
    }
}

open class OFFile: OFSeekableStream {
    public static let INVALID_FILE_HANDLE: Int32 = -1
    
    internal var _handle: Int32 = OFFile.INVALID_FILE_HANDLE
    internal var _atEndOfStream: Bool = false
    
    public convenience init(withPath filePath: String, mode: String) throws {
        var flags = parseMode(mode)
        flags |= O_BINARY | O_CLOEXEC
        
        var handle: Int32
        
        #if os(Windows)
        handle = filePath.withCString(encodedAs: UTF16.self) {
            return _wopen($0, flags, _S_IREAD | _S_IWRITE)
        }
        #elseif os(Linux)
        handle = open64(filePath, flags, mode_t(0o666))
        #else
        
        handle = open(filePath, flags, mode_t(0o666))
        #endif
        
        guard handle != -1 else {
            throw OFException.openFailed(path: filePath, mode: mode, error: errno)
        }
        
        self.init(withHandle: handle)
    }
    
    public required init(withHandle handle: Int32) {
        _handle = handle
    }
    
    open override func lowLevelIsAtEndOfStream() throws -> Bool {
        guard _handle != OFFile.INVALID_FILE_HANDLE else {
            throw OFException.notOpen(stream: self)
        }
        
        return _atEndOfStream
    }
    
    open override func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        guard _handle != OFFile.INVALID_FILE_HANDLE else {
            throw OFException.notOpen(stream: self)
        }
        
        var ret: Int
        
        #if os(Windows)
        guard length <= UInt32.max else {
            throw OFException.outOfRange
        }
            
        ret = MinGWCrt.read(_handle, buffer, UInt32(length))
        #elseif os(Linux)
        ret = Glibc.read(_handle, buffer, length)
        #else
        ret = Darwin.read(_handle, buffer, length)
        #endif
        
        guard ret >= 0 else {
            throw OFException.readFailed(stream: self, requestedLength: length, error: errno)
        }
        
        if ret == 0 {
            _atEndOfStream = true
        }
        
        return ret
    }
    
    open override func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        guard _handle != OFFile.INVALID_FILE_HANDLE else {
            throw OFException.notOpen(stream: self)
        }
        
        var bytesWriten: Int
        
        #if os(Windows)
        guard length <= Int32.max else {
            throw OFException.outOfRange
        }
        
        let _bytesWriten = MinGWCrt.write(_handle, buffer, Int32(length))
        bytesWriten = Int(_bytesWriten)
        #elseif os(Linux)
        bytesWriten = Glibc.write(_handle, buffer, length)
        #else
        bytesWriten = Darwin.write(_handle, buffer, length)
        #endif
        
        guard bytesWriten >= 0 else {
            throw OFException.writeFailed(stream: self, requestedLength: length, bytesWritten: 0, error: errno)
        }
        
        return bytesWriten
    }
    
    open override func lowLevelSeek(to offset: OFSeekableStream.offset_t, whence: Int32) throws -> OFSeekableStream.offset_t {
        guard _handle != OFFile.INVALID_FILE_HANDLE else {
            throw OFException.notOpen(stream: self)
        }
        
        var ret: OFSeekableStream.offset_t
        
        #if os(Windows)
        ret = _lseeki64(_handle, offset, whence)
        #elseif os(Linux)
        ret = lseek64(_handle, offset, whence)
        #else
        ret = lseek(_handle, offset, whence)
        #endif
        
        guard ret != -1 else {
            throw OFException.seekFailed(stream: self, offset: offset, whence: whence, error: errno)
        }
        
        _atEndOfStream = false
        
        return ret
    }
    
    open override func close() throws {
        if _handle != OFFile.INVALID_FILE_HANDLE {
            #if os(Windows)
            MinGWCrt.close(_handle)
            #elseif os(Linux)
            Glibc.close(_handle)
            #else
            Darwin.close(_handle)
            #endif
        }
        
        _handle = OFFile.INVALID_FILE_HANDLE
        
        try super.close()
    }
    
    deinit {
        try! self.close()
    }
}
