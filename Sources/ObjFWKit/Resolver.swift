//
//  Resolver.swift
//  StreamsKit
//
//  Created by Yury Vovk on 10.05.2018.
//

import Foundation

#if os(Windows)
import CWin32
#endif

fileprivate class __ResolverResultStorage {
    var _addrinfo: UnsafeMutablePointer<addrinfo>!
    
    init?(_ addrinfo: UnsafeMutablePointer<addrinfo>?) {
        guard addrinfo != nil else {
            return nil
        }
        
        _addrinfo = addrinfo
    }
    
    deinit {
        freeaddrinfo(_addrinfo)
    }
}


public enum Resolver {
    
    public struct AddressInfo {
        private var _info: UnsafeMutablePointer<addrinfo>!
        
        public var family: OFStreamSocket.SocketProtocolFamily! {
            return OFStreamSocket.SocketProtocolFamily(rawValue: _info.pointee.ai_family)
        }
        
        public var socketType: OFStreamSocket.SocketType! {
            return OFStreamSocket.SocketType(rawValue: _info.pointee.ai_socktype)
        }
        
        public var `protocol`: OFStreamSocket.SocketProtocol! {
            return OFStreamSocket.SocketProtocol(rawValue: _info.pointee.ai_protocol)
        }
        
        public var address: UnsafeMutablePointer<sockaddr>! {
            return _info.pointee.ai_addr
        }
        
        public var addressLength: socklen_t {
            return _info.pointee.ai_addrlen
        }
        
        public var flags: Int32 {
            return _info.pointee.ai_flags
        }
        
        private init() {
            
        }
        
        internal init?(_ info: UnsafeMutablePointer<addrinfo>?) {
            guard info != nil else {
                return nil
            }
            
            _info = info
        }
    }
    
    public struct ResolverResults: Sequence {
        private var _results: __ResolverResultStorage!
        
        internal init?(_ results: UnsafeMutablePointer<addrinfo>?) {
            guard results != nil else {
                return nil
            }
            
            _results = __ResolverResultStorage(results)
        }
        
        public func makeIterator() -> AnyIterator<Resolver.AddressInfo> {
            var _info = _results._addrinfo
            
            return AnyIterator {
                let info = _info
                
                if info != nil {
                    _info = info!.pointee.ai_next
                }
                
                return Resolver.AddressInfo(info)
            }
        }
        
        public var count: Int {
            var result: Int = 0
            
            var next = _results._addrinfo
            while next != nil {
                result += 1
                next = next?.pointee.ai_next
            }
            
            return result
        }
        
        public subscript(index: Int) -> Resolver.AddressInfo {
            precondition(self.count != 0 && index < self.count, "Index \(index) out of range!")
            
            for (i, info) in self.enumerated() {
                if i == index {
                    return info
                }
            }
            
            fatalError("Index is invalid")
        }
    }
    
    fileprivate static let _lock = NSLock()
    
    public static func resolve(host: String, port: UInt16, type: OFStreamSocket.SocketType) throws -> ResolverResults? {
        
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = type.rawValue
        hints.ai_flags = AI_NUMERICSERV
        
        var res0: UnsafeMutablePointer<addrinfo>? = nil
       
        
        let portString = "\(port)"
        
        var error: Int32 = 0
        
        withUnsafeMutablePointer(to: &res0) {
            error = getaddrinfo(host, portString, UnsafeMutablePointer(&hints), $0)
        }
        
        guard error == 0 else {
            throw OFException.addressTranslationFailed(host: host, error: errno)
        }
        
        var count: Int = 0
        
        var res: UnsafeMutablePointer<addrinfo>! = res0
        
        while res != nil {
            count += 1
            res = res.pointee.ai_next
        }
        
        guard count != 0 else {
            freeaddrinfo(res0)
            throw OFException.addressTranslationFailed(host: host, error: errno)
        }
        
        
        
        return ResolverResults(res0)
    }
    
    public static func addressToStringAndPort(_ addr: UnsafePointer<sockaddr>!, addressLength length: socklen_t) throws -> (host: String, port: UInt16) {
        
        var hostCString = UnsafeMutablePointer<CChar>.allocate(capacity: Int(NI_MAXHOST))
        hostCString.initialize(to: 0)
        var portCString = UnsafeMutablePointer<CChar>.allocate(capacity: Int(NI_MAXSERV))
        portCString.initialize(to: 0)
        
        defer {
            hostCString.deallocate(capacity: Int(NI_MAXHOST))
            portCString.deallocate(capacity: Int(NI_MAXSERV))
        }
        
        var error: Int32
        #if os(Windows)
        error = getnameinfo(addr, length, hostCString, DWORD(NI_MAXHOST), portCString, DWORD(NI_MAXSERV), NI_NUMERICHOST | NI_NUMERICSERV)
        #else
        error = getnameinfo(addr, length, hostCString, socklen_t(NI_MAXHOST), portCString, socklen_t(NI_MAXSERV), NI_NUMERICHOST | NI_NUMERICSERV)
        #endif
        
        let host = String(utf8String: hostCString)!
        
        let tmp = Int(String(utf8String: portCString)!)!
        
        guard tmp <= UInt16.max else {
            throw OFException.outOfRange()
        }
        
        let port = UInt16(tmp)
        
        return (host, port)
    }
    
    public static func getSockName(_ socket: OFStreamSocket.Socket, _ addr: UnsafeMutablePointer<sockaddr>!, _ addrlen: UnsafeMutablePointer<socklen_t>!) -> Bool {
        _lock.lock()
        
        defer {
            _lock.unlock()
        }
        
        let ret = getsockname(socket.rawValue, addr, addrlen)
        
        return ret == 0
    }
}

