//
//  Stream.swift
//  StreamsKit
//
//  Created by Yury Vovk on 08.05.2018.
//

import Foundation

open class Stream {
    public enum ByteOrder {
        case bigEndian
        case littleEndian
        
        public static let current: Stream.ByteOrder = {
            let number: UInt32 = 0x12345678
            
            if number == number.bigEndian {
                return .bigEndian
            } else {
                return .littleEndian
            }
        }()
    }
    
    internal static let MIN_READ_SIZE = 512
    
    
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
    
    open var writeBuffered: Bool = false
    internal var _blocking: Bool = true
    
    open var isBlocking: Bool {
        get {
            return _blocking
        }
    }
    
    open func setBlocking(_ enable: Bool) throws {
        throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
    }
    
    open func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
    }
    
    @discardableResult
    open func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
    }
    
    open func lowLevelIsAtEndOfStream() throws -> Bool {
        throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
    }
    
    open func atEndOfStream() throws -> Bool {
        if _readBufferLength > 0 {
            return true
        }
        
        return try self.lowLevelIsAtEndOfStream()
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
    
    open func read(into buffer: inout UnsafeMutableRawPointer, exactLength length: Int) throws {
        var readLength = Int(0)
        
        while readLength < length {
            if try self.atEndOfStream() {
                throw StreamsKitError.truncatedData()
            }
            
            var tmp = buffer + readLength
            readLength += try self.read(into: &tmp, length: length - readLength)
        }
    }
    
    open func write(buffer: UnsafeRawPointer, length: Int) throws {
        if !writeBuffered {
            let bytesWritten = try self.lowLevelWrite(buffer, length: length)
            
            if _blocking && bytesWritten < length {
                throw StreamsKitError.writeFailed(stream: self, requestedLength: length, bytesWritten: bytesWritten, error: 0)
            }
        } else {
            _writeBuffer = self._resizeIntenalBuffer(_writeBuffer, size: _writeBufferLength + length)
            _writeBuffer.baseAddress!.advanced(by: _writeBufferLength).copyBytes(from: buffer, count: length)
            _writeBufferLength += length
        }
    }
    
    open func read<T>(byteOrder: Stream.ByteOrder = .current) throws -> T where T: FixedWidthInteger {
        func BSWAP_IF_LE(_ val: T) -> T {
            if Stream.ByteOrder.current == .littleEndian {
                return val.bigEndian
            } else {
                return val
            }
        }
        
        func BSWAP_IF_BE(_ val: T) -> T {
            if Stream.ByteOrder.current == .bigEndian {
                return val.littleEndian
            } else {
                return val
            }
        }
        
        let length = MemoryLayout<T>.size
        var buffer = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: MemoryLayout<T>.alignment)
        
        try self.read(into: &buffer, exactLength: length)
        
        let result: T = buffer.assumingMemoryBound(to: T.self).pointee
        
        switch byteOrder {
        case .bigEndian:
            return BSWAP_IF_LE(result)
        case .littleEndian:
            return BSWAP_IF_BE(result)
        }
    }
    
    open func read(byteOrder: Stream.ByteOrder = .current) throws -> Float {
        let value: UInt32 = try self.read()
        
        if ByteOrder.current != byteOrder {
            return CFConvertFloatSwappedToHost(CFSwappedFloat32(v: value))
        } else {
            return Float(bitPattern: value)
        }
    }
    
    open func read(byteOrder: Stream.ByteOrder = .current) throws -> Double {
        let value: UInt64 = try self.read()
        
        if ByteOrder.current != byteOrder {
            return CFConvertDoubleSwappedToHost(CFSwappedFloat64(v: value))
        } else {
            return Double(bitPattern: value)
        }
    }
    
    open func read<T>(into buffer: inout UnsafeMutablePointer<T>, count: Int, byteOrder: Stream.ByteOrder = .current) throws -> Int where T: FixedWidthInteger {
        guard count <= Int.max / MemoryLayout<T>.size else {
            throw StreamsKitError.outOfRange()
        }
        
        func BSWAP_IF_LE(_ val: T) -> T {
            if Stream.ByteOrder.current == .littleEndian {
                return val.bigEndian
            } else {
                return val
            }
        }
        
        func BSWAP_IF_BE(_ val: T) -> T {
            if Stream.ByteOrder.current == .bigEndian {
                return val.littleEndian
            } else {
                return val
            }
        }
        
        let bufferLength = MemoryLayout<T>.size * count
        var tmp = UnsafeMutableRawPointer.allocate(bytes: bufferLength, alignedTo: MemoryLayout<T>.alignment)
        
        defer {
            tmp.deallocate(bytes: bufferLength, alignedTo: MemoryLayout<T>.alignment)
        }
        
        try self.read(into: &tmp, exactLength: bufferLength)
        
        let destination = UnsafeMutableBufferPointer(start: buffer, count: count)
        let source = UnsafeMutableBufferPointer(start: tmp.assumingMemoryBound(to: T.self), count: count)
        
        var _swap: (T) -> T
        
        switch byteOrder {
        case .bigEndian:
            _swap = BSWAP_IF_LE
        case .littleEndian:
            _swap = BSWAP_IF_BE
        }
        
        for (i, value) in source.enumerated() {
            destination[i] = _swap(value)
        }
        
        return bufferLength
    }
    
    open func read(into buffer: inout UnsafeMutablePointer<Float>, count: Int, byteOrder: Stream.ByteOrder = .current) throws -> Int {
        guard count <= Int.max / MemoryLayout<Float>.size else {
            throw StreamsKitError.outOfRange()
        }
        
        let bufferLength = MemoryLayout<UInt32>.size * count
        var tmp = UnsafeMutableRawPointer.allocate(bytes: bufferLength, alignedTo: MemoryLayout<UInt32>.alignment)
        
        defer {
            tmp.deallocate(bytes: bufferLength, alignedTo: MemoryLayout<UInt32>.alignment)
        }
        
        try self.read(into: &tmp, exactLength: bufferLength)
        
        let destination = UnsafeMutableBufferPointer(start: buffer, count: count)
        let source = UnsafeMutableBufferPointer(start: tmp.assumingMemoryBound(to: UInt32.self), count: count)
        
        for (i, item) in source.enumerated() {
            if ByteOrder.current != byteOrder {
                destination[i] = CFConvertFloatSwappedToHost(CFSwappedFloat32(v: item))
            } else {
                destination[i] = Float(bitPattern: item)
            }
        }
        
        return bufferLength
    }
    
    open func read(into buffer: inout UnsafeMutablePointer<Double>, count: Int, byteOrder: Stream.ByteOrder = .current) throws -> Int {
        guard count <= Int.max / MemoryLayout<Double>.size else {
            throw StreamsKitError.outOfRange()
        }
        
        let bufferLength = MemoryLayout<UInt64>.size * count
        var tmp = UnsafeMutableRawPointer.allocate(bytes: bufferLength, alignedTo: MemoryLayout<UInt64>.alignment)
        
        defer {
            tmp.deallocate(bytes: bufferLength, alignedTo: MemoryLayout<UInt64>.alignment)
        }
        
        try self.read(into: &tmp, exactLength: bufferLength)
        
        let destination = UnsafeMutableBufferPointer(start: buffer, count: count)
        let source = UnsafeMutableBufferPointer(start: tmp.assumingMemoryBound(to: UInt64.self), count: count)
        
        for (i, item) in source.enumerated() {
            if ByteOrder.current != byteOrder {
                destination[i] = CFConvertDoubleSwappedToHost(CFSwappedFloat64(v: item))
            } else {
                destination[i] = Double(bitPattern: item)
            }
        }
        
        return bufferLength
    }
    
    open func readData(withCount count: Int) throws -> Data {
        
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
    
    open func close() throws {
        if _writeBuffer != nil {
            _writeBuffer.deallocate()
        }
        
        if _readBufferMemmory != nil {
            _readBuffer = nil
            _readBufferMemmory.deallocate()
        }
        
        _readBufferLength = 0
        _writeBufferLength = 0
        self.writeBuffered = false
    }
}
