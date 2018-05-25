//
//  InputStream.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 25.05.2018.
//

import Foundation


open class OFInputStream: InputStream {
    internal var _ofStream: OFStream!
    internal var _error: Error?
    internal var _status: Stream.Status!
    
    public init(ofStream: OFStream) {
        _ofStream = ofStream
        
        _status = Stream.Status.open
        
        super.init(data: Data())
    }
    
    open override func open() {
        guard _ofStream != nil else {
            super.close()
            return
        }
        
        _status = Stream.Status.open
    }
    
    open override func close() {
        guard _ofStream != nil else {
            super.close()
            return
        }
        
        _status = Stream.Status.closed
    }
    
    override open var streamError: Error? {
        guard _ofStream != nil else {
            return super.streamError
        }
        
        return _error
    }
    
    open override var streamStatus: Stream.Status {
        guard _ofStream != nil else {
            return super.streamStatus
        }
        
        return _status
    }
    
    open override var hasBytesAvailable: Bool {
        
        guard _ofStream != nil else {
            return super.hasBytesAvailable
        }
        
        guard _status == Stream.Status.open || _status == Stream.Status.reading else {
            return false
        }
        
        do {
            let hasBytes = try _ofStream.atEndOfStream()
            
            if !hasBytes {
                _status = Stream.Status.atEnd
            }
            
            return hasBytes
            
        } catch {
            _error = error
            _status = Stream.Status.error
        }
        
        return false
    }
    
    open override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard _ofStream != nil else {
            return super.read(buffer, maxLength: len)
        }
        
        var length = Int(-1)
        
        guard _status == Stream.Status.open || _status == Stream.Status.reading || _status == Stream.Status.atEnd else {
            return -1
        }
        
        guard _status != Stream.Status.atEnd else {
            return 0
        }
        
        _status = Stream.Status.reading
        
        var tmp = UnsafeMutableRawPointer.allocate(bytes: len, alignedTo: MemoryLayout<UInt8>.alignment)
        
        defer {
            tmp.deallocate(bytes: len, alignedTo: MemoryLayout<UInt8>.alignment)
        }
        
        do {
            length = try _ofStream.readIntoBuffer(&tmp, length: len)
            
            buffer.assign(from: tmp.assumingMemoryBound(to: UInt8.self), count: length)
            
            if try _ofStream.atEndOfStream() {
                _status = Stream.Status.atEnd
            } else {
                _status = Stream.Status.open
            }
            
        } catch {
            _error = error
            _status = Stream.Status.error
        }
        
        return length
    }
    
    open override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool {
        guard _ofStream != nil else {
            return super.getBuffer(buffer, length: len)
        }
        
        guard _status == Stream.Status.open || _status == Stream.Status.reading || _status == Stream.Status.atEnd else {
            buffer.pointee = nil
            len.pointee = -1
            return false
        }
        
        guard _status != Stream.Status.atEnd else {
            buffer.pointee = nil
            len.pointee = 0
            return false
        }
        
        _status = Stream.Status.reading
        
        var result = false
        
        var tmp = UnsafeMutableRawPointer.allocate(bytes: len.pointee, alignedTo: MemoryLayout<UInt8>.alignment)
        
        do {
            
            let length = try _ofStream.readIntoBuffer(&tmp, length: len.pointee)
            
            len.pointee = length
            buffer.pointee = tmp.assumingMemoryBound(to: UInt8.self)
            result = true
            
            if try _ofStream.atEndOfStream() {
                _status = Stream.Status.atEnd
            } else {
                _status = Stream.Status.open
            }
            
        } catch {
            _error = error
            _status = Stream.Status.error
        }
        
        return result
    }
    
    open override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoopMode) {
        aRunLoop.execute(inMode: mode) {
            StreamObserver.current._scheduleInputStream(self._ofStream)
        }
    }
    
    open override func remove(from aRunLoop: RunLoop, forMode mode: RunLoopMode) {
        aRunLoop.execute(inMode: mode) {
            StreamObserver.current._removeObjectForReading(self._ofStream)
        }
    }
}
