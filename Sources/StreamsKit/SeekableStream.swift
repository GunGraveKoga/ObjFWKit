//
//  SeekableStream.swift
//  StreamsKit
//
//  Created by Yury Vovk on 08.05.2018.
//

import Foundation

open class SeekableStream: StreamsKit.Stream {
    
    open func lowLevelSeek(to offset: Int, whence: Int32) throws -> Int {
        fatalError("Not implemented")
    }
    
    open func seek(to offset: Int, whence: Int32) throws -> Int {
        var _offset = offset
        
        if whence == SEEK_CUR {
            _offset -= _readBufferLength
        }
        
        _offset = try self.lowLevelSeek(to: _offset, whence: whence)
        
        _readBuffer = nil
        _readBufferMemmory.deallocate()
        _readBufferMemmory = nil
        _readBufferLength = 0
        
        return _offset
    }
}
