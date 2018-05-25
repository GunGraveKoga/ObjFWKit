//
//  StreamObserver.swift
//  ObjFWKitPackageDescription
//
//  Created by Yury Vovk on 22.05.2018.
//

import Foundation


public protocol QueueItem {
    mutating func handleObject(_ object: AnyObject?) -> Bool
}

public typealias OFAsyncReadBufferBlock = (OFStream, UnsafeMutableRawPointer, Int, Error?) -> Bool

internal struct ReadQueueItem: QueueItem {
    private var _block: OFAsyncReadBufferBlock
    private var _buffer: UnsafeMutableRawPointer
    private var _length: Int
    
    init(_ buffer: UnsafeMutableRawPointer, _ length: Int, _ block: @escaping OFAsyncReadBufferBlock) {
        self._buffer = buffer
        self._length = length
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var length = Int(0)
        var exception: Error? = nil
        var shouldContinue = false
        
        repeat {
            do {
                length = try stream.readIntoBuffer( &_buffer, length: _length)
            } catch {
                exception = error
            }
            
            shouldContinue = _block(stream, _buffer, length, exception)
            
            do {
                if try stream.atEndOfStream() {
                    return (exception == nil) ? shouldContinue : false
                }
                
            } catch {
                _buffer.initializeMemory(as: UInt8.self, to: 0)
                return _block(stream, _buffer, -1, error)
            }
            
            length = 0
            exception = nil
            
        } while shouldContinue
        
        return shouldContinue
    }
}

internal struct ExactReadQueueItem: QueueItem {
    private var _block: OFAsyncReadBufferBlock
    private var _buffer: UnsafeMutableRawPointer
    private var _exactLength: Int
    private var _readLength = Int(0)
    
    init(_ buffer: UnsafeMutableRawPointer, _ exactLength: Int, _ block: @escaping OFAsyncReadBufferBlock) {
        self._buffer = buffer
        self._exactLength = exactLength
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var length = Int(0)
        var exception: Error? = nil
        var shouldContinue = false
        
        repeat {
            
            do {
                var buffer = _buffer.advanced(by: _readLength)
                length = try stream.readIntoBuffer( &buffer, length: _exactLength - _readLength)
                
            } catch {
                exception = error
            }
            _readLength += length
            
            do {
                if _readLength != _exactLength, try !stream.atEndOfStream() && exception == nil {
                    return true
                }
            } catch {
                _ = _block(stream, _buffer, length, error)
                
                return false
            }
            
            shouldContinue = _block(stream, _buffer, length, exception)
            
            do {
                if try stream.atEndOfStream() {
                    return shouldContinue
                }
            } catch {
                _buffer.initializeMemory(as: UInt8.self, to: 0)
                _ = _block(stream, _buffer, -1, error)
                
                return false
            }
            
            length = 0
            exception = nil
            
        } while shouldContinue
        
        return shouldContinue
    }
}

public typealias OFAsyncReadLineBlock = (OFStream, String?, Error?) -> Bool

internal struct ReadLineQueueItem: QueueItem {
    private var _encoding: String.Encoding
    private var _block: OFAsyncReadLineBlock
    
    init(_ encoding: String.Encoding, _ block: @escaping OFAsyncReadLineBlock) {
        self._block = block
        self._encoding = encoding
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var line: String? = nil
        var exception: Error?  = nil
        var shouldContinue = false
        
        repeat {
            do {
                line = try stream.tryReadLine(withEncoding: _encoding)
            } catch {
                exception = error
            }
            
            do {
                if line == nil, try !stream.atEndOfStream() && exception == nil {
                    return true
                }
            } catch {
                return _block(stream, line, error)
            }
            
            shouldContinue = _block(stream, line, exception)
            
            do {
                if try stream.atEndOfStream() {
                    return shouldContinue
                }
            } catch {
                return _block(stream, nil, error)
            }
            
            line = nil
            exception = nil
            
        } while shouldContinue
        
        return shouldContinue
    }
}

internal struct AcceptQueueItem: QueueItem {
    private var _block: (OFTCPSocket, OFTCPSocket?, Error?) -> Bool
    
    init(_ block: @escaping (OFTCPSocket, OFTCPSocket?, Error?) -> Bool) {
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let listeningSocket = object as! OFTCPSocket
        
        var newSocket: OFTCPSocket? = nil
        var exception: Error? = nil
        
        do {
            newSocket = try listeningSocket.accept()
        } catch {
            exception = error
        }
        
        return _block(listeningSocket, newSocket, exception)
    }
}

public typealias OFAsyncWriteBufferBlock = (OFStream, UnsafeMutablePointer<UnsafeRawPointer>, Int, Error?) -> Int

internal struct WriteQueueItem: QueueItem {
    private var _block: OFAsyncWriteBufferBlock
    private var _buffer: UnsafeRawPointer
    private var _length: Int
    private var _writtenLength = Int(0)
    
    init(_ buffer: UnsafeRawPointer, _ length: Int, _ block: @escaping OFAsyncWriteBufferBlock) {
        self._block = block
        self._buffer = buffer
        self._length = length
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        guard let stream = object as? OFStream else {
            return false
        }
        
        var length = Int(0)
        var exception: Error? = nil
        
        do {
            let buffer = _buffer.advanced(by: _writtenLength)
            length = try stream.write(buffer: buffer, length: _length - _writtenLength)
        } catch {
            exception = error
        }
        
        _writtenLength += length
        
        if _writtenLength != length && exception == nil {
            return true
        }
        
        var buffer = _buffer
        
        return withUnsafeMutablePointer(to: &buffer) {
            _length = _block(stream, $0, _writtenLength, exception)
            
            if _length == 0 {
                return false
            }
            
            _writtenLength = 0
            _buffer = $0.pointee
            
            return true
        }
    }
}

public typealias OFUDPAsyncReceiveBlock = (OFUDPSocket, UnsafeMutableRawPointer, Int, SocketAddress?, Error?) -> Bool

internal struct UDPReceiveQueueItem: QueueItem {
    private var _block: OFUDPAsyncReceiveBlock
    private var _buffer: UnsafeMutableRawPointer
    private var _length: Int
    
    init(_ buffer: UnsafeMutableRawPointer, _ length: Int, _ block: @escaping OFUDPAsyncReceiveBlock) {
        self._buffer = buffer
        self._length = length
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFUDPSocket
        
        var length = Int(0)
        var receiver: SocketAddress? = nil
        var exception: Error? = nil
        var shouldContinue = false
        
        repeat {
            do {
                let (length_, receiver_) = try stream.receive(into: &_buffer, length: _length)
                length = length_
                receiver = receiver_
            } catch {
                exception = error
            }
            
            if length == 0 && exception == nil {
                return true
            }
            
            shouldContinue = _block(stream, _buffer, length, receiver, exception)
            
            if (length == 0) {
                return shouldContinue
            }
            
        } while shouldContinue
        
        return shouldContinue
    }
}

public typealias OFUDPAsyncSendBlock = (OFUDPSocket, UnsafeMutablePointer<UnsafeRawPointer>, Int, SocketAddress, Error?) -> Int

internal struct UDPSendQueueItem: QueueItem {
    private var _block: OFUDPAsyncSendBlock
    private var _buffer: UnsafeRawPointer
    private var _length: Int
    private var _receiver: SocketAddress
    
    init(_ buffer: UnsafeRawPointer, _ length: Int, _ receiver: SocketAddress, _ block: @escaping OFUDPAsyncSendBlock) {
        self._block = block
        self._buffer = buffer
        self._length = length
        self._receiver = receiver
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFUDPSocket
        
        var exception: Error? = nil
        
        do {
            try stream.send(buffer: _buffer, length: _length, receiver: _receiver)
        } catch {
            exception = error
        }
        
        var buffer = _buffer
        
        return withUnsafeMutablePointer(to: &buffer) {
            _length = _block(stream, $0, (exception == nil) ? _length : 0, _receiver, exception)
            
            if _length == 0 {
                return false
            }
            
            _buffer = $0.pointee
            
            return true
        }
    }
}


fileprivate let CurrentObserverKey = "OFCurrentObserverKey"

public final class StreamObserver {
    public class var current: StreamObserver {
        get {
            if let current = Thread.current.threadDictionary[CurrentObserverKey] {
                return current as! StreamObserver
            }
            
            let currentObserver = StreamObserver()
            
            Thread.current.threadDictionary[CurrentObserverKey] = currentObserver
            
            return currentObserver
        }
    }
    
    private var _lock: NSLock = NSLock()
    
    private var _readQueue: [CFRunLoopSource: (AnyObject, [QueueItem])] = [CFRunLoopSource: (AnyObject, [QueueItem])]()
    private var _writeQueue: [CFRunLoopSource: (AnyObject, [QueueItem])] = [CFRunLoopSource: (AnyObject, [QueueItem])]()
    
    internal func _addAsyncReadForStream(_ stream: OFStream, buffer: UnsafeMutableRawPointer, length: Int, block: @escaping OFAsyncReadBufferBlock) {
        
        guard let _ = stream as? OFReadyForReadingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = ReadQueueItem(buffer, length, block)
        
        self._addObjectForReading(stream, withQueueItem: queueItem)
    }
    
    internal func _addAsyncReadForStream(_ stream: OFStream, buffer: UnsafeMutableRawPointer, exactLength length: Int, block: @escaping OFAsyncReadBufferBlock) {
        
        guard let _ = stream as? OFReadyForReadingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = ExactReadQueueItem(buffer, length, block)
        
        self._addObjectForReading(stream, withQueueItem: queueItem)
    }
    
    internal func _addAsyncReadLineForStream(_ stream: OFStream, encoding: String.Encoding, block: @escaping OFAsyncReadLineBlock) {
        
        guard let _ = stream as? OFReadyForReadingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = ReadLineQueueItem(encoding, block)
        
        self._addObjectForReading(stream, withQueueItem: queueItem)
    }
    
    internal func _addAsyncWriteForStream(_ stream: OFStream, buffer: UnsafeRawPointer, length: Int, block: @escaping OFAsyncWriteBufferBlock) {
        
        guard let _ = stream as? OFReadyForWritingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = WriteQueueItem(buffer, length, block)
        
        self._addObjectForWriting(stream, withQueueItem: queueItem)
    }
    
    internal func _addAsyncAcceptForTCPSocket(_ socket: OFTCPSocket, block: @escaping (OFTCPSocket, OFTCPSocket?, Error?) -> Bool) {
        
        let queueItem = AcceptQueueItem(block)
        
        socket._socket.enableCallBacks([.acceptCallBack])
        
        self._addObjectForReading(socket, withQueueItem: queueItem)
    }
    
    internal func _addAsyncReceiveForUDPSocket(_ socket: OFUDPSocket, buffer: UnsafeMutableRawPointer, length: Int, block: @escaping OFUDPAsyncReceiveBlock) {
        
        guard let _ = socket as? OFReadyForReadingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = UDPReceiveQueueItem(buffer, length, block)
        
        self._addObjectForReading(socket, withQueueItem: queueItem)
    }
    
    internal func _addAsyncSendForUDPSocket(_ socket: OFUDPSocket, buffer: UnsafeRawPointer, length: Int, receiver: SocketAddress, block: @escaping OFUDPAsyncSendBlock) {
        
        guard let _ = socket as? OFReadyForWritingObserving else {
            preconditionFailure("Not implemented")
        }
        
        let queueItem = UDPSendQueueItem.init(buffer, length, receiver, block)
        
        self._addObjectForWriting(socket, withQueueItem: queueItem)
    }
    
    private func _addObjectForReading<I: QueueItem>(_ object: AnyObject, withQueueItem item: I) {
        let readingObject = object as! OFReadyForReadingObserving
        
        _lock.lock()
        
        if _readQueue[readingObject.sourceForReading] == nil {
            _readQueue[readingObject.sourceForReading] = (object, [item])
        } else {
            _readQueue[readingObject.sourceForReading]!.1.append(item)
        }
        
        _lock.unlock()
        
        self._processReadBuffers()
        
        let runLoop = RunLoop.current.getCFRunLoop()
        
        CFRunLoopAddSource(runLoop, readingObject.sourceForReading, CFRunLoopMode.commonModes)
        
        CFRunLoopWakeUp(runLoop)
    }
    
    public func addObjectForReading<T: OFReadyForReadingObserving, I: QueueItem>(_ object: T, withQueueItem item: I) {
        
        self._addObjectForReading(object, withQueueItem: item)
    }
    
    private func _removeObjectForReading(_ object: AnyObject) {
        let objectToRemove = object as! OFReadyForReadingObserving
        
        guard _readQueue[objectToRemove.sourceForReading] != nil else {
            preconditionFailure("Deleting empty read queue for source \(objectToRemove.sourceForReading)")
        }
        
        _readQueue[objectToRemove.sourceForReading]!.1.removeAll()
    }
    
    public func sourceReadyForReading(_ source: CFRunLoopSource) {
        self._processReadQueue(forSource: source)
    }
    
    private func _addObjectForWriting<I: QueueItem>(_ object: AnyObject, withQueueItem item: I) {
        let writingObject = object as! OFReadyForWritingObserving
        
        _lock.lock()
        
        if _writeQueue[writingObject.sourceForWriting] == nil {
            _writeQueue[writingObject.sourceForWriting] = (object, [item])
        } else {
            _writeQueue[writingObject.sourceForWriting]!.1.append(item)
        }
        
        _lock.unlock()
        
        let runLoop = RunLoop.current.getCFRunLoop()
        
        CFRunLoopAddSource(runLoop, writingObject.sourceForWriting, CFRunLoopMode.defaultMode)
        
        CFRunLoopWakeUp(runLoop)
    }
    
    public func addObjectForWriting<T: OFReadyForWritingObserving, I: QueueItem>(_ object: T, withQueueItem item: I) {
        
        self._addObjectForWriting(object, withQueueItem: item)
    }
    
    private func _removeObjectForWriting(_ object: AnyObject) {
        let objectToRemove = object as! OFReadyForWritingObserving
        
        guard _writeQueue[objectToRemove.sourceForWriting] != nil else {
            preconditionFailure("Deleting empty write queue for source \(objectToRemove.sourceForWriting)")
        }
        
        _writeQueue[objectToRemove.sourceForWriting]!.1.removeAll()
    }
    
    public func sourceReadyForWriting(_ object: CFRunLoopSource) {
        self._processWriteQueue(forSource: object)
    }
    
    private func _processReadBuffers() {
        for (object, queue) in _readQueue {
            if type(of: queue.0) == OFStream.self {
                let stream = queue.0 as! OFStream
                
                if stream.hasDataInReadBuffer && !stream.of_waitForDelimiter() {
                    self._processReadQueue(forSource: object)
                }
            }
        }
    }
    
    private func _processReadQueue(forSource source: CFRunLoopSource) {
        guard _readQueue[source] != nil else {
            preconditionFailure("Empty read queue for source \(source)!")
        }
        
        if var first = _readQueue[source]!.1.first {
            if !first.handleObject(_readQueue[source]!.0) {
                if _readQueue[source]!.1.count > 0 {
                    
                    _readQueue[source]!.1.removeFirst()
                    
                    if type(of: _readQueue[source]!.0) == OFStream.self {
                        let stream = _readQueue[source]!.0 as! OFStream
                        
                        if stream.hasDataInReadBuffer && !stream.of_waitForDelimiter() {
                            self._processReadQueue(forSource: source)
                        }
                    }
                }
            }
        }
    }
    
    private func _processWriteQueue(forSource source: CFRunLoopSource) {
        guard _writeQueue[source] != nil else {
            preconditionFailure("Empty write queue for source \(source)")
        }
        
        if var first = _writeQueue[source]!.1.first {
            if !first.handleObject(_writeQueue[source]!.0) {
                if _writeQueue[source]!.1.count > 0 {
                    
                    _writeQueue[source]!.1.removeFirst()
                }
            }
        }
    }
    
    internal func _cancelAsyncRequestsForObject(_ object: AnyObject) {
        _lock.lock()
        
        defer {
            _lock.unlock()
        }
        
        var source: CFRunLoopSource! = nil
        
        if let readingObject = object as? OFReadyForReadingObserving {
            if _readQueue.keys.contains(readingObject.sourceForReading) {
                self._removeObjectForReading(object)
                
                source = readingObject.sourceForReading
            }
        }
        
        if let writingObject = object as? OFReadyForWritingObserving {
            if _writeQueue.keys.contains(writingObject.sourceForWriting) {
                self._removeObjectForWriting(object)
                
                source = writingObject.sourceForWriting
            }
        }
        
        if source != nil {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), source, CFRunLoopMode.commonModes)
        }
    }
}
