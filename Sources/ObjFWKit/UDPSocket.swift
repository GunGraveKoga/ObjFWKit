//
//  OFUDPSocket.swift
//  StreamsKit
//
//  Created by Yury Vovk on 17.05.2018.
//

import Foundation

fileprivate let __OFUDPSocketObserverCallback: CFSocketCallBack = {(socketObject: CFSocket?, callbackType: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) -> Swift.Void in
    
    let observer = Unmanaged<OFUDPSocketObserver>.fromOpaque(info!).takeUnretainedValue()
    
    if callbackType.contains(.readCallBack) {
        observer.readyForReading()
    }
    
    if callbackType.contains(.writeCallBack) {
        observer.readyForWriting()
    }
}

fileprivate final class OFUDPSocketObserver<T>: OFStreamObserver where T: OFUDPSocket {
    private var _socket: CFSocket!
    private var _socketSource: CFRunLoopSource!
    
    convenience init?(withSocket socket: T) {
        self.init(stream: socket)
    }
    
    required init?(stream: AnyObject) {
        guard let stream = stream as? T else {
            return nil
        }
        
        super.init(stream: stream)
        
        let unmanaged = Unmanaged<OFUDPSocketObserver>.passUnretained(self)
        
        var context = CFSocketContext(version: 0, info: unmanaged.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callbackType: CFSocketCallBackType = [.readCallBack, .writeCallBack]
        
        _socket = CFSocketCreateWithNative(nil, stream._socket.rawValue, callbackType.rawValue, __OFUDPSocketObserverCallback, &context)
        
        guard _socket != nil else {
            return nil
        }
        
        _socketSource = CFSocketCreateRunLoopSource(nil, _socket, 0)
        
        guard _socketSource != nil else {
            return nil
        }
    }
    
    override func observe() {
        #if os(macOS)
            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), _socketSource, CFRunLoopMode.commonModes)
        #else
            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), _socketSource, CFRunLoopMode.commonModes.rawValue)
        #endif
    }
    
    override func cancelObserving() {
        CFSocketInvalidate(_socket)
        super.cancelObserving()
    }
}

open class OFUDPSocket {
    internal var _socket: OFStreamSocket.Socket!
    internal var _observer: OFStreamObserver!
    
    public required init() {
        
    }
    
    open class func resolveAddressForHost(_ host: String, port: UInt16) throws -> OFStreamSocket.SocketAddress? {
        guard let results = try Resolver.resolve(host: host, port: port, type: .datagram) else {
            return nil
        }
        
        return OFStreamSocket.SocketAddress(results[0].address)
    }
    
    open class func asyncResolveAddressForHost(_ host: String, port: UInt16, _ body: @escaping (String, UInt16, OFStreamSocket.SocketAddress?, Error?) -> Swift.Void) {
        
        let runloop = RunLoop.current
        
        Thread.asyncExecute {
            var _error: Error? = nil
            var _address: OFStreamSocket.SocketAddress? = nil
            
            do {
                _address = try self.resolveAddressForHost(host, port: port)
            } catch {
                _error = error
            }
            
            runloop.execute {
                body(host, port, _address, _error)
            }
        }
    }
    
    open class func getHostAndPortForAddress(address: inout OFStreamSocket.SocketAddress) throws -> (host: String, port: UInt16) {
        return try address.withSockAddrPointer {
            return try Resolver.addressToStringAndPort($0, addressLength: $1)
        }
    }
    
    open func bindToHost(_ host: String, port: UInt16 = 0) throws -> UInt16 {
        guard _socket == nil else {
            throw OFException.alreadyConnected(stream: self)
        }
        
        guard let results = try Resolver.resolve(host: host, port: port, type: .datagram) else {
            throw OFException.bindFailed(host: host, port: port, socket: self, error: _socket_errno())
        }
        
        if let address = OFStreamSocket.SocketAddress(results[0].address) {
            _socket = OFStreamSocket.Socket(family: results[0].family, type: results[0].socketType, protocol: results[0].protocol)
            
            guard _socket != nil else {
                throw OFException.bindFailed(host: host, port: port, socket: self, error: _socket_errno())
            }
            
            if SOCK_CLOEXEC == 0 {
                #if !os(Windows)
                    var flags: Int32 = 0
                    flags = fcntl(_socket.rawValue, F_GETFD, 0)
                    
                    if flags != -1 {
                        _ = fcntl(_socket.rawValue, F_SETFD, flags | FD_CLOEXEC)
                    }
                #endif
            }
            
            var one:Int32 = 1
            _ = withUnsafePointer(to: &one) {
                setsockopt(_socket.rawValue, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
            }
            
            guard BindSocket(_socket, onAddress: address) else {
                let error = _socket_errno()
                CloseSocket(_socket)
                _socket = nil
                
                throw OFException.bindFailed(host: host, port: port, socket: self, error: error)
            }
            
            if port > 0 {
                self._observer = OFUDPSocketObserver(withSocket: self)
                return port
            }
            
            let boundAddress = try OFStreamSocket.SocketAddress {
                guard Resolver.getSockName(_socket, $0, $1) else {
                    let error = _socket_errno()
                    CloseSocket(_socket)
                    _socket = nil
                    
                    throw OFException.bindFailed(host: host, port: port, socket: self, error: error)
                }
            }
            
            switch boundAddress {
            case .ipv4(var _address):
                return withUnsafeMutablePointer(to: &_address) {
                    self._observer = OFUDPSocketObserver(withSocket: self)
                    return $0.pointee.sin_port
                }
            case .ipv6(var _address):
                return withUnsafeMutablePointer(to: &_address) {
                    self._observer = OFUDPSocketObserver(withSocket: self)
                    return $0.pointee.sin6_port
                }
            default:
                break
            }
            
            CloseSocket(_socket)
            _socket = nil
            
            throw OFException.bindFailed(host: host, port: port, socket: self, error: EAFNOSUPPORT)
            
        } else {
            throw OFException.bindFailed(host: host, port: port, socket: self, error: EHOSTUNREACH)
        }
    }
    
    open func receive(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> (length: Int, sender: OFStreamSocket.SocketAddress) {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        #if os(Windows)
            guard length <= Int32.max else {
                throw OFException.outOfRange()
            }
        #endif
        
        var tmp = UnsafeMutableRawPointer.allocate(bytes: length, alignedTo: MemoryLayout<UInt8>.alignment)
        
        defer {
            tmp.deallocate(bytes: length, alignedTo: MemoryLayout<UInt8>.alignment)
        }
        
        var ret = Int(-1)
        let sender = OFStreamSocket.SocketAddress {
            #if !os(Windows)
                ret = recvfrom(_socket.rawValue, tmp, length, 0, $0, $1)
            #else
                let _ret = recvfrom(_socket.rawValue, tmp, Int32(length), 0, $0, $1)
                ret = Int(_ret)
            #endif
        }
        
        guard ret >= 0 else {
            throw OFException.readFailed(stream: self, requestedLength: length, error: _socket_errno())
        }
        
        buffer.copyBytes(from: tmp, count: ret)
        
        return (ret, sender)
    }
    
    open func asyncReceive(into buffer: inout UnsafeMutableRawPointer, length: Int, _ body: @escaping (OFUDPSocket, UnsafeMutableRawPointer, Int, OFStreamSocket.SocketAddress?, Error?) -> Bool) {
        
        if self._observer != nil {
            self._observer.addReadItem(UDPReceiveQueueItem(buffer, length, body))
            
            self._observer.startObserving()
        }
    }
    
    open func send(buffer: UnsafeRawPointer, length: Int, receiver: OFStreamSocket.SocketAddress) throws {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        #if os(Windows)
            guard length <= Int32.max else {
                throw OFException.outOfRange()
            }
        #endif
        
        let bytesWritten = receiver.withSockAddrPointer { (addr, len) -> Int in
            #if !os(Windows)
                return sendto(_socket.rawValue, buffer, length, 0, addr, len)
            #else
                let _bytesWritten = sendto(_socket.rawValue, buffer, Int32(length), 0, addr, len)
                return Int(_bytesWritten)
            #endif
        }
        
        guard bytesWritten == length else {
            throw OFException.writeFailed(stream: self, requestedLength: length, bytesWritten: bytesWritten, error: _socket_errno())
        }
    }
    
    open func asyncSend(buffer: inout UnsafeRawPointer, length: Int, receiver: OFStreamSocket.SocketAddress, _ body: @escaping (OFUDPSocket, UnsafeMutablePointer<UnsafeRawPointer>, Int, OFStreamSocket.SocketAddress, Error?) -> Int) {
        
        if self._observer != nil {
            self._observer.addWriteItem(UDPSendQueueItem(buffer, length, receiver, body))
            
            self._observer.startObserving()
        }
    }
    
    open func close() throws {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        CloseSocket(_socket)
        _socket = nil
    }
    
    deinit {
        if _socket != nil {
            try! self.close()
        }
    }
}
