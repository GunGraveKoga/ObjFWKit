//
//  OutputStream.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 25.05.2018.
//

import Foundation


open class OFOutputStream: OutputStream {
    internal var _ofStream: OFStream!
    internal var _error: Error?
    internal var _status: Stream.Status!
    
    internal var _properties: [Stream.PropertyKey: AnyObject] = [Stream.PropertyKey: AnyObject]()
    
    public init(ofStream: OFStream) {
        
        _ofStream = ofStream
        
        _status = Stream.Status.open
        
        super.init(toMemory: ())
    }
    
    open override func open() {
        guard _ofStream != nil else {
            super.close()
            return
        }
        
        _status = .open
    }
    
    open override func close() {
        guard _ofStream != nil else {
            super.close()
            return
        }
        
        _status = .closed
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
    
    open override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        guard _ofStream != nil else {
            return super.write(buffer, maxLength: len)
        }
        
        guard _status == .open || _status == .writing else {
            return -1
        }
        
        _status = .writing
        
        var length = Int(-1)
        
        do {
            length = try _ofStream.writeBuffer(buffer, length: len)
            
            if length == 0 {
                _status = .atEnd
            } else {
                _status = .open
            }
            
        } catch {
            _error = error
            _status = .error
        }
        
        return len
    }
    
    open override var hasSpaceAvailable: Bool {
        guard _ofStream != nil else {
            return super.hasSpaceAvailable
        }
        
        guard _status == .open || _status == .writing else {
            return false
        }
        
        return true
    }
    
    open override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoopMode) {
        aRunLoop.execute(inMode: mode) {
            StreamObserver.current._scheduleOutputStream(self._ofStream)
        }
    }
    
    open override func remove(from aRunLoop: RunLoop, forMode mode: RunLoopMode) {
        aRunLoop.execute(inMode: mode) {
            StreamObserver.current._removeObjectForWriting(self._ofStream)
        }
    }
    
}
