//
//  SeekableStream.swift
//  StreamsKit
//
//  Created by Yury Vovk on 08.05.2018.
//

import Foundation

open class SeekableStream: StreamsKit.Stream {
    #if os(Windows)
    public typealias offset_t = __int64
    #elseif os(Linux)
    public typealias offset_t = off64_t
    #else
    public typealias offset_t = off_t
    #endif
    
    open func lowLevelSeek(to offset: SeekableStream.offset_t, whence: Int32) throws -> SeekableStream.offset_t {
        throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
    }
    
    open func seek(to offset: SeekableStream.offset_t, whence: Int32) throws -> SeekableStream.offset_t {
        var _offset = offset
        
        if whence == SEEK_CUR {
            _offset -= SeekableStream.offset_t(_readBufferLength)
        }
        
        _offset = try self.lowLevelSeek(to: _offset, whence: whence)
        
        _readBuffer = nil
        _readBufferMemmory.deallocate()
        _readBufferMemmory = nil
        _readBufferLength = 0
        
        return _offset
    }
}
