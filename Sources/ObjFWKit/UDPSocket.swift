//
//  OFUDPSocket.swift
//  StreamsKit
//
//  Created by Yury Vovk on 17.05.2018.
//

import Foundation

open class OFUDPSocket {
    internal var _socket: OFStreamSocket.Socket!
    
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
    
    open func bindToHost(_ host: String, port: UInt16) throws -> UInt16 {
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
                    return $0.pointee.sin_port
                }
            case .ipv6(var _address):
                return withUnsafeMutablePointer(to: &_address) {
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
    
    open func receive(into buffer: inout UnsafeMutableRawPointer, length: Int, sender: inout OFStreamSocket.SocketAddress) throws -> Int {
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
        
        let ret = sender.withSockAddrPointer{ (addr, len) -> Int in
            var _len = len
            return withUnsafeMutablePointer(to: &_len) {
                #if !os(Windows)
                    return recvfrom(_socket.rawValue, tmp, length, 0, addr, $0)
                #else
                    let _ret = recvfrom(_socket.rawValue, tmp, Int32(length), 0, addr, $0)
                    return Int(_ret)
                #endif
            }
        }
        
        guard ret >= 0 else {
            throw OFException.readFailed(stream: self, requestedLength: length, error: _socket_errno())
        }
        
        buffer.copyBytes(from: tmp, count: ret)
        
        return ret
    }
    
    open func send(buffer: UnsafeRawPointer, length: Int, receiver: inout OFStreamSocket.SocketAddress) throws {
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
