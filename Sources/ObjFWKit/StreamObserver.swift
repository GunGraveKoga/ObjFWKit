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

internal struct ReadQueueItem: QueueItem {
    private var _block: (OFStream, UnsafeMutableRawPointer, Int, Error?) -> Bool
    private var _buffer: UnsafeMutableRawPointer
    private var _length: Int
    
    init(_ buffer: UnsafeMutableRawPointer, _ length: Int, _ block: @escaping (OFStream, UnsafeMutableRawPointer, Int, Error?) -> Bool) {
        self._buffer = buffer
        self._length = length
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var length = Int(0)
        var exception: Error? = nil
        
        do {
            try length = stream.read(into: &_buffer, length: _length)
        } catch {
            exception = error
        }
        
        return _block(stream, _buffer, length, exception)
    }
}

internal struct ExactReadQueueItem: QueueItem {
    private var _block: (OFStream, UnsafeMutableRawPointer, Int, Error?) -> Bool
    private var _buffer: UnsafeMutableRawPointer
    private var _exactLength: Int
    private var _readLength = Int(0)
    
    init(_ buffer: UnsafeMutableRawPointer, _ exactLength: Int, _ block: @escaping (OFStream, UnsafeMutableRawPointer, Int, Error?) -> Bool) {
        self._buffer = buffer
        self._exactLength = exactLength
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var length = Int(0)
        var exception: Error? = nil
        
        do {
            var buffer = _buffer.advanced(by: _readLength)
            try length = stream.read(into: &buffer, length: _exactLength - _readLength)
        } catch {
            exception = error
        }
        
        _readLength += length
        
        if _readLength != _exactLength && !(try! stream.atEndOfStream()) && exception == nil {
            return true
        }
        
        return _block(stream, _buffer, length, exception)
    }
}

internal struct ReadLineQueueItem: QueueItem {
    private var _encoding: String.Encoding
    private var _block: (OFStream, String?, Error?) -> Bool
    
    init(_ encoding: String.Encoding, _ block: @escaping (OFStream, String?, Error?) -> Bool) {
        self._block = block
        self._encoding = encoding
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let stream = object as! OFStream
        
        var line: String? = nil
        var exception: Error?  = nil
        
        do {
            line = try stream.tryReadLine(withEncoding: _encoding)
        } catch {
            exception = error
        }
        
        if line == nil && !(try! stream.atEndOfStream()) && exception == nil {
            return true
        }
        
        return _block(stream, line, exception)
    }
}

internal struct AcceptQueueItem<T>: QueueItem where T: OFTCPSocket {
    private var _block: (T, T?, Error?) -> Bool
    
    init(_ block: @escaping (T, T?, Error?) -> Bool) {
        self._block = block
    }
    
    mutating func handleObject(_ object: AnyObject?) -> Bool {
        let listeningSocket = object as! T
        
        var newSocket: T? = nil
        var exception: Error? = nil
        
        do {
            newSocket = try listeningSocket.accept()
        } catch {
            exception = error
        }
        
        return _block(listeningSocket, newSocket, exception)
    }
}

internal struct WriteQueueItem: QueueItem {
    private var _block: (OFStream, UnsafeMutablePointer<UnsafeRawPointer>, Int, Error?) -> Int
    private var _buffer: UnsafeRawPointer
    private var _length: Int
    private var _writtenLength = Int(0)
    
    init(_ buffer: UnsafeRawPointer, _ length: Int, _ block: @escaping (OFStream, UnsafeMutablePointer<UnsafeRawPointer>, Int, Error?) -> Int) {
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

open class OFStreamObserver {
    internal weak var stream: AnyObject?
    internal var readQueue = [QueueItem]()
    internal var writeQueue = [QueueItem]()
    internal var lock: NSRecursiveLock
    
    public required init?(stream: AnyObject) {
        self.stream = stream
        self.lock = NSRecursiveLock()
    }
    
    open func addReadItem(_ item: QueueItem) {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        self.readQueue.append(item)
    }
    
    open func addWriteItem(_ item: QueueItem) {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        self.writeQueue.append(item)
    }
    
    open func readyForReading() {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        if var firstItem = self.readQueue.first {
            if !firstItem.handleObject(self.stream) {
                if let _ = self.readQueue.first {
                    self.readQueue.removeFirst()
                }
            }
        }
    }
    
    open func readyForWriting() {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        if var firstItem = self.writeQueue.first {
            if !firstItem.handleObject(self.stream) {
                if let _ = self.writeQueue.first {
                    self.writeQueue.removeFirst()
                }
            }
        }
    }
    
    open func processReadBuffer() {
        if let _stream = self.stream as? OFStream {
            if _stream.hasDataInReadBuffer && !_stream.of_waitForDelimiter() {
                self.readyForReading()
            }
        }
    }
    
    open func startObserving() {
        self.processReadBuffer()
        
        self.observe()
    }
    
    open func observe() {
        fatalError("Not implemented")
    }
    
    open func cancelObserving() {
        self.lock.lock()
        
        defer {
            self.lock.unlock()
        }
        
        if self.readQueue.count > 0 {
            self.readQueue.removeAll()
        }
        
        if self.writeQueue.count > 0 {
            self.writeQueue.removeAll()
        }
    }
    
    deinit {
        self.cancelObserving()
    }
}
