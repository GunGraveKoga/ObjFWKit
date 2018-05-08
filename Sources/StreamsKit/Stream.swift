//
//  Stream.swift
//  StreamsKit
//
//  Created by Yury Vovk on 08.05.2018.
//

import Foundation

open class Stream {
    
    internal static var MIN_READ_SIZE = 512
    
    
    internal var _readBufferLength: Int = 0
    internal var _readBufferMemmory: UnsafeMutableRawBufferPointer!
    internal var _readBuffer: UnsafeMutableRawPointer!
    
    internal var _writeBufferLength: Int = 0
    internal var _writeBuffer: UnsafeMutableRawBufferPointer!
    
    internal func _resizeIntenalBuffer(_ buffer: UnsafeMutableRawBufferPointer?, size: Int) -> UnsafeMutableRawBufferPointer {
        
        if buffer == nil {
            return UnsafeMutableRawBufferPointer.allocate(count: size)
        }
        
        defer {
            buffer!.deallocate()
        }
        
        let newBuffer = UnsafeMutableRawBufferPointer.allocate(count: buffer!.count + size)
        newBuffer.baseAddress!.copyBytes(from: buffer!.baseAddress!, count: buffer!.count)
        
        return newBuffer
    }
    
    public enum StreamsKitError<StreamType>: Error where StreamType: StreamsKit.Stream {
        case writeFailed(stream: StreamType, requestedLength: Int, bytesWritten: Int, errNo: Int32)
    }
    
    open var writeBuffered: Bool = false
    open var blocking: Bool = true
    
    open func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        fatalError("Not implemeted")
    }
    
    @discardableResult
    open func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        fatalError("Not implemented")
    }
    
    open var lowLevelIsAtEndOfStream: Bool {
        get {
            fatalError("Not implemented")
        }
    }
    
    open var atEndOfStream: Bool {
        get {
            if _readBufferLength > 0 {
                return true
            }
            
            return self.lowLevelIsAtEndOfStream
        }
    }
    
    open var hasDataInReadBuffer: Bool {
        return _readBufferLength > 0
    }
    
    open func read(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        if _readBufferLength == 0 {
            if length < Stream.MIN_READ_SIZE {
                var tmp = UnsafeMutableRawPointer.allocate(bytes: Stream.MIN_READ_SIZE, alignedTo: MemoryLayout<UInt8>.size)
                tmp.initializeMemory(as: UInt8.self, to: 0)
                
                defer {
                    tmp.deallocate(bytes: Stream.MIN_READ_SIZE, alignedTo: MemoryLayout<UInt8>.size)
                }
                
                let bytesRead = try self.lowLevelRead(into: &tmp, length: Stream.MIN_READ_SIZE)
                
                if bytesRead > length {
                    buffer.copyBytes(from: tmp, count: length)
                    
                    let readBuffer = UnsafeMutableRawBufferPointer.allocate(count: bytesRead - length)
                    readBuffer.baseAddress!.copyBytes(from: tmp + length, count: bytesRead - length)
                    
                    _readBufferMemmory = readBuffer
                    _readBuffer = _readBufferMemmory.baseAddress
                    _readBufferLength = bytesRead - length
                    
                } else {
                    buffer.copyBytes(from: tmp, count: bytesRead)
                }
            }
            
            return try self.lowLevelRead(into: &buffer, length: length)
        }
        
        if length >= _readBufferLength {
            let ret = _readBufferLength
            
            buffer.copyBytes(from: _readBuffer, count: _readBufferLength)
            _readBuffer = nil
            _readBufferLength = 0
            _readBufferMemmory.deallocate()
            _readBufferMemmory = nil
            
            return ret
        } else {
            buffer.copyBytes(from: _readBuffer, count: length)
            _readBuffer = _readBuffer.advanced(by: length)
            _readBufferLength -= length
            
            return length
        }
    }
    
    @discardableResult
    open func write(buffer: UnsafeRawPointer, length: Int) throws -> Int {
        if !writeBuffered {
            let bytesWritten = try self.lowLevelWrite(buffer, length: length)
            
            if blocking && bytesWritten < length {
                throw StreamsKitError.writeFailed(stream: self, requestedLength: length, bytesWritten: bytesWritten, errNo: 0)
            }
            
            return bytesWritten
        } else {
            _writeBuffer = self._resizeIntenalBuffer(_writeBuffer, size: _writeBufferLength + length)
            _writeBuffer.baseAddress!.advanced(by: _writeBufferLength).copyBytes(from: buffer, count: length)
            _writeBufferLength += length
            
            return length
        }
    }
    
    open func flushWriteBuffer() throws {
        guard _writeBuffer != nil else {
            return
        }
        
        try self.lowLevelWrite(_writeBuffer.baseAddress!, length: _writeBufferLength)
        
        _writeBuffer.deallocate()
        _writeBuffer = nil
        _writeBufferLength = 0
    }
    
    deinit {
        if _writeBuffer != nil {
            _writeBuffer.deallocate()
        }
        
        if _readBufferMemmory != nil {
            _readBuffer = nil
            _readBufferMemmory.deallocate()
        }
    }
}
