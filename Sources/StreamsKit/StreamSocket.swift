//
//  StreamSocket.swift
//  StreamsKit
//
//  Created by Yury Vovk on 10.05.2018.
//

import Foundation

#if os(Windows)
import CWin32
#endif

#if !os(Linux)
    public let SOCK_CLOEXEC: Int32 = 0
#endif

internal func _socket_errno() -> Int32 {
    #if os(Windows)
        switch WSAGetLastError() {
        case WSAEACCES:
            return EACCES
        case WSAEADDRINUSE:
            return EADDRINUSE
        case WSAEADDRNOTAVAIL:
            return EADDRNOTAVAIL
        case WSAEAFNOSUPPORT:
            return EAFNOSUPPORT
        case WSAEALREADY:
            return EALREADY
        case WSAEBADF:
            return EBADF
        case WSAECONNABORTED:
            return ECONNABORTED
        case WSAECONNREFUSED:
            return ECONNREFUSED
        case WSAECONNRESET:
            return ECONNRESET
        case WSAEDESTADDRREQ:
            return EDESTADDRREQ
        case WSAEDISCON:
            return EPIPE
        case WSAEDQUOT:
            return EDQUOT
        case WSAEFAULT:
            return EFAULT
        case WSAEHOSTDOWN:
            return EHOSTDOWN
        case WSAEHOSTUNREACH:
            return EHOSTUNREACH
        case WSAEINPROGRESS:
            return EINPROGRESS
        case WSAEINTR:
            return EINTR
        case WSAEINVAL:
            return EINVAL
        case WSAEISCONN:
            return EISCONN
        case WSAELOOP:
            return ELOOP
        case WSAEMSGSIZE:
            return EMSGSIZE
        case WSAENAMETOOLONG:
            return ENAMETOOLONG
        case WSAENETDOWN:
            return ENETDOWN
        case WSAENETRESET:
            return ENETRESET
        case WSAENETUNREACH:
            return ENETUNREACH
        case WSAENOBUFS:
            return ENOBUFS
        case WSAENOPROTOOPT:
            return ENOPROTOOPT
        case WSAENOTCONN:
            return ENOTCONN
        case WSAENOTEMPTY:
            return ENOTEMPTY
        case WSAENOTSOCK:
            return ENOTSOCK
        case WSAEOPNOTSUPP:
            return EOPNOTSUPP
        case WSAEPFNOSUPPORT:
            return EPFNOSUPPORT
        case WSAEPROCLIM:
            return EPROCLIM
        case WSAEPROTONOSUPPORT:
            return EPROTONOSUPPORT
        case WSAEPROTOTYPE:
            return EPROTOTYPE
        case WSAEREMOTE:
            return EREMOTE
        case WSAESHUTDOWN:
            return ESHUTDOWN
        case WSAESOCKTNOSUPPORT:
            return ESOCKTNOSUPPORT
        case WSAESTALE:
            return ESTALE
        case WSAETIMEDOUT:
            return ETIMEDOUT
        case WSAETOOMANYREFS:
            return ETOOMANYREFS
        case WSAEUSERS:
            return EUSERS
        case WSAEWOULDBLOCK:
            return EWOULDBLOCK
        default:
            return 0
        }
    #endif
    return errno
}

#if os(Windows)
internal func MAKEWORD(_ low: BYTE, _ high: BYTE) -> WORD {
    return WORD(low) | (WORD(high) << 8)
}
#endif

#if os(Windows)
internal func _IOW<T>(_ x: UInt32, _ y: UInt32, _ t: T.Type) -> Int {
    return Int((CWin32.IOC_IN | UInt32((Int32(MemoryLayout<T>.size) & CWin32.IOCPARM_MASK) << 16)) | ((x  << 8) | y))
}

internal let FIONBIO = _IOW("f".unicodeScalars.first!.value, 126, CWin32.u_long.self)
#endif

internal var hash_seed: Int {
    get {
        var seed: Int = 0
        
        while seed == 0 {
            #if os(macOS)
                seed = Int(arc4random())
            #else
                var t = timeval()
                
                withUnsafeMutablePointer(to: &t) {
                    gettimeofday($0, nil)
                }
                srand(UInt32(t.tv_sec) ^ UInt32(t.tv_usec))
                
                hash = Int(UInt32(rand() << 16) | UInt32(rand() & 0xFFFF))
            #endif
        }
        
        return seed
    }
}

public func CloseSocket(_ socket: StreamSocket.Socket) {
    #if os(Windows)
        closesocket(socket.rawValue)
    #else
        close(socket.rawValue)
    #endif
}

public func AcceptSocket(_ socket: StreamSocket.Socket) -> (acceptedSocket: StreamSocket.Socket?, acceptedSocketAddress: StreamSocket.SocketAddress) {
    let address = StreamSocket.SocketAddress()
    
    let rawSocket = address.withSockAddrPointer {(addr, len) -> StreamSocket.Socket.RawValue in
        var _len = len
        return withUnsafeMutablePointer(to: &_len) {
            return accept(socket.rawValue, addr, $0)
        }
    }
    
    return (StreamSocket.Socket(rawValue: rawSocket), address)
}

public func ListenOnSocket(_ socket: StreamSocket.Socket, withBacklog backlog: Int) -> Bool {
    return listen(socket.rawValue, Int32(backlog)) != -1
}

public func BindSocket(_ socket: StreamSocket.Socket, onAddress address: StreamSocket.SocketAddress) -> Bool {
    return address.withSockAddrPointer {
        return bind(socket.rawValue, $0, $1) == 0
    }
}

public func ConnectSocket(_ socket: StreamSocket.Socket, toAddress address: StreamSocket.SocketAddress) -> Bool {
    return address.withSockAddrPointer {
        return connect(socket.rawValue, $0, $1) != -1
    }
}

open class StreamSocket: StreamsKit.Stream {
    
    public enum SocketProtocolFamily: RawRepresentable {
        public typealias RawValue = Int32
        
        case inet
        case inet6
        #if !os(Windows)
        case unix
        #endif
        case unspecified
        
        public init?(rawValue: Int32) {
            #if !os(Windows)
                switch rawValue {
                case AF_INET:
                    self = .inet
                case AF_INET6:
                    self = .inet6
                case AF_UNIX:
                    self = .unix
                case AF_UNSPEC:
                    self = .unspecified
                default:
                    return nil
                }
            #else
                switch rawValue {
                case AF_INET:
                    self = .inet
                case AF_INET6:
                    self = .inet6
                case AF_UNSPEC:
                    self = .unspecified
                default:
                    return nil
                }
            #endif
        }
        
        public var rawValue: Int32 {
            #if !os(Windows)
                switch self {
                case .inet:
                    return AF_INET
                case .inet6:
                    return AF_INET6
                case .unix:
                    return AF_UNIX
                case .unspecified:
                    return AF_UNSPEC
                }
            #else
                switch self {
                case .inet:
                    return AF_INET
                case .inet6:
                    return AF_INET6
                case .unspecified:
                    return AF_UNSPEC
                }
            #endif
        }
    }
    
    public enum SocketProtocol: RawRepresentable {
        public typealias RawValue = Int32
        
        case tcp
        case udp
        #if !os(Windows)
        case unix
        #endif
        
        public init?(rawValue: Int32) {
            #if !os(Windows)
                switch rawValue {
                case Int32(IPPROTO_TCP):
                    self = .tcp
                case Int32(IPPROTO_UDP):
                    self = .udp
                case Int32(0):
                    self = .unix
                default:
                    return nil
                }
            #else
                switch rawValue {
                case IPPROTO_TCP:
                    self = .tcp
                case IPPROTO_UDP:
                    self = .udp
                default:
                    return nil
                }
            #endif
        }
        
        public var rawValue: Int32 {
            get {
                #if !os(Windows)
                    switch self {
                    case .tcp:
                        return Int32(IPPROTO_TCP)
                    case .udp:
                        return Int32(IPPROTO_UDP)
                    case .unix:
                        return Int32(0)
                    }
                #else
                    switch self {
                    case .tcp:
                        return IPPROTO_TCP
                    case .udp:
                        return IPPROTO_UDP
                    }
                #endif
            }
        }
        
    }
    
    public enum SocketType: RawRepresentable {
        public typealias RawValue = Int32
        
        case stream
        case datagram
        case raw
        
        public init?(rawValue: Int32) {
            #if os(Linux)
                switch rawValue {
                case Int32(SOCK_STREAM.rawValue):
                    self = .stream
                case Int32(SOCK_DGRAM.rawValue):
                    self = .datagram
                case Int32(SOCK_RAW.rawValue):
                    self = .raw
                default:
                    return nil
                }
            #else
                switch rawValue {
                case SOCK_STREAM:
                    self = .stream
                case SOCK_DGRAM:
                    self = .datagram
                case SOCK_RAW:
                    self = .raw
                default:
                    return nil
                }
            #endif
        }
        
        public var rawValue: Int32 {
            switch self {
            case .stream:
                #if os(Linux)
                    return Int32(SOCK_STREAM.rawValue)
                #else
                    return SOCK_STREAM
                #endif
            case .datagram:
                #if os(Linux)
                    return Int32(SOCK_DGRAM.rawValue)
                #else
                    return SOCK_DGRAM
                #endif
            case .raw:
                #if os(Linux)
                    return Int32(SOCK_RAW.rawValue)
                #else
                    return SOCK_RAW
                #endif
            }
        }
    }
    
    public enum SocketAddress: Hashable, Equatable {
        
        case ipv4(sockaddr_in)
        case ipv6(sockaddr_in6)
        case unix(sockaddr_un)
        case storage(sockaddr_storage)
        
        public var size: socklen_t {
            get {
                switch self {
                case .ipv4(_):
                    return socklen_t(MemoryLayout<sockaddr_in>.size)
                case .ipv6(_):
                    return socklen_t(MemoryLayout<sockaddr_in6>.size)
                case .unix(_):
                    return socklen_t(MemoryLayout<sockaddr_un>.size)
                case .storage(_):
                    return socklen_t(MemoryLayout<sockaddr_storage>.size)
                }
            }
        }
        
        public var family: StreamSocket.SocketProtocolFamily? {
            switch self {
            case .ipv6(_):
                return .inet6
            case .ipv4(_):
                return .inet
            case .unix(_):
                return .unix
            case .storage(let address):
                do {
                    return StreamSocket.SocketProtocolFamily(rawValue: Int32(address.ss_family))
                }
            }
        }
        
        public var hashValue: Int {
            var hash = hash_seed
            
            #if !os(Windows)
                switch self {
                case .ipv4(let address):
                    do {
                        hash += Int(address.sin_family)
                        hash += Int(address.sin_port << 1)
                        hash ^= Int(address.sin_addr.s_addr)
                    }
                case .ipv6(var address):
                    do {
                        hash += Int(address.sin6_family)
                        hash += Int(address.sin6_port << 1)
                        
                        var subhash = hash_seed
                        
                        #if os(Linux)
                            let s6_addr = UnsafeBufferPointer(start: &address.sin6_addr.in6_u.u6_addr8.0, count: MemoryLayout.size(ofValue: address.sin6_addr.in6_u.u6_addr8))
                        #else
                            let s6_addr = UnsafeBufferPointer(start: &address.sin6_addr.__u6_addr.__u6_addr8.0, count: MemoryLayout.size(ofValue: address.sin6_addr.__u6_addr.__u6_addr8))
                        #endif
                        
                        for item in s6_addr {
                            subhash += Int(item)
                            subhash += Int(subhash << 10)
                            subhash ^= Int(subhash >> 6)
                        }
                        
                        subhash += Int(subhash << 3)
                        subhash ^= Int(subhash >> 11)
                        subhash += Int(subhash << 15)
                        
                        hash ^= subhash
                    }
                case .unix(var address):
                    do {
                        hash += Int(address.sun_family)
                        hash += Int(address.sun_len)
                        
                        var subhash = hash_seed
                        
                        let unix_path = UnsafeBufferPointer(start: &address.sun_path.0, count: MemoryLayout.size(ofValue: address.sun_path))
                        
                        for item in unix_path {
                            subhash += Int(item)
                            subhash += Int(subhash << 10)
                            subhash ^= Int(subhash >> 6)
                        }
                        
                        subhash += Int(subhash << 3)
                        subhash ^= Int(subhash >> 11)
                        subhash += Int(subhash << 15)
                        
                        hash ^= subhash
                    }
                default:
                    return 0
                }
            #else
                switch self {
                case .ipv4(let address):
                    do {
                        hash += Int(address.sin_family)
                        hash += Int(address.sin_port << 1)
                        hash ^= Int(address.sin_addr.s_addr)
                    }
                case .ipv6(var address):
                    do {
                        hash += Int(address.sin6_family)
                        hash += Int(address.sin6_port << 1)
                        
                        var subhash = hash_seed
                        
                        
                        let s6_addr = UnsafeBufferPointer(start: &address.sin6_addr.u.Byte.0, count: MemoryLayout.size(ofValue: address.sin6_addr.u.Byte))
                        
                        for item in s6_addr {
                            subhash += Int(item)
                            subhash += Int(subhash << 10)
                            subhash ^= Int(subhash >> 6)
                        }
                        
                        subhash += Int(subhash << 3)
                        subhash ^= Int(subhash >> 11)
                        subhash += Int(subhash << 15)
                        
                        hash ^= subhash
                    }
                default:
                    return 0
                }
            #endif
            
            return hash
        }
        
        public init() {
            self.init(sockaddr_storage())
        }
        
        public init?(_ address: UnsafeMutablePointer<sockaddr>?) {
            guard let _address = address else {
                return nil
            }
            
            guard let family = StreamSocket.SocketProtocolFamily(rawValue: Int32(_address.pointee.sa_family)) else {
                return nil
            }
            
            #if !os(Windows)
                switch family {
                case .inet:
                    self = _address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        return StreamSocket.SocketAddress.ipv4($0.pointee)
                    }
                case .inet6:
                    self = _address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        return StreamSocket.SocketAddress.ipv6($0.pointee)
                    }
                case .unix:
                    self = _address.withMemoryRebound(to: sockaddr_un.self, capacity: 1) {
                        return StreamSocket.SocketAddress.unix($0.pointee)
                    }
                default:
                    return nil
                }
            #else
                switch family {
                case .inet:
                    self = _address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        return StreamSocket.SocketAddress.ipv4($0.pointee)
                    }
                case .inet6:
                    self = _address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        return StreamSocket.SocketAddress.ipv6($0.pointee)
                    }
                default:
                    return nil
                }
            #endif
        }
        
        public init(_ address: sockaddr_storage) {
            if let family = SocketProtocolFamily(rawValue: Int32(address.ss_family)) {
                var _address = address
                #if !os(Windows)
                    switch family {
                    case .inet:
                        self = withUnsafeMutablePointer(to: &_address) {
                            return $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                                return StreamSocket.SocketAddress.ipv4($0.pointee)
                            }
                        }
                    case .inet6:
                        self = withUnsafeMutablePointer(to: &_address) {
                            return $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                                return StreamSocket.SocketAddress.ipv6($0.pointee)
                            }
                        }
                    case .unix:
                        self = withUnsafeMutablePointer(to: &_address) {
                            return $0.withMemoryRebound(to: sockaddr_un.self, capacity: 1) {
                                return StreamSocket.SocketAddress.unix($0.pointee)
                            }
                        }
                    case .unspecified:
                        self = .storage(address)
                    }
                #else
                    switch family {
                    case .inet:
                        self = withUnsafeMutablePointer(to: &_address) {
                            return $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                                return StreamSocket.SocketAddress.ipv4($0.pointee)
                            }
                        }
                    case .inet6:
                        self = withUnsafeMutablePointer(to: &_address) {
                            return $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                                return StreamSocket.SocketAddress.ipv6($0.pointee)
                            }
                        }
                    case .unspecified:
                        self = .storage(address)
                    }
                #endif
            } else {
                self = .storage(address)
            }
        }
        
        public init(_ addressProvider: (UnsafeMutablePointer<sockaddr>, UnsafeMutablePointer<socklen_t>) throws -> Swift.Void) rethrows {
            var address = sockaddr_storage()
            var addressLength = socklen_t(MemoryLayout.size(ofValue: address))
            
            try withUnsafeMutablePointer(to: &address) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {addressPointer in
                    try withUnsafeMutablePointer(to: &addressLength) {addressLengthPointer in
                        try addressProvider(addressPointer, addressLengthPointer)
                    }
                }
            }
            
            self.init(address)
        }
        
        public func withSockAddrPointer<R>(_ body: (UnsafeMutablePointer<sockaddr>, socklen_t) throws -> R) rethrows -> R {
            func castAndCall<T>(_ address: T, _ body: (UnsafeMutablePointer<sockaddr>, socklen_t) throws -> R) rethrows -> R {
                var _address = address
                
                return try withUnsafeMutablePointer(to: &_address) {
                    return try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        return try body($0, socklen_t(MemoryLayout<T>.size))
                    }
                }
            }
            
            #if !os(Windows)
                switch self {
                case .ipv4(let address):
                    return try castAndCall(address, body)
                case .ipv6(let address):
                    return try castAndCall(address, body)
                case .unix(let address):
                    return try castAndCall(address, body)
                case .storage(let address):
                    return try castAndCall(address, body)
                }
            #else
                switch self {
                case .ipv4(let address):
                    return try castAndCall(address, body)
                case .ipv6(let address):
                    return try castAndCall(address, body)
                case .storage(let address):
                    return try castAndCall(address, body)
                }
            #endif
        }
        
        public static func ==(lhs: StreamSocket.SocketAddress, rhs: StreamSocket.SocketAddress) -> Bool {
            #if !os(Windows)
                switch (lhs, rhs) {
                case let (.ipv4(l_addr), .ipv4(r_addr)):
                    do {
                        if l_addr.sin_port != r_addr.sin_port {
                            return false
                        }
                        
                        if l_addr.sin_addr.s_addr != r_addr.sin_addr.s_addr {
                            return false
                        }
                    }
                case var (.ipv6(l_addr), .ipv6(r_addr)):
                    do {
                        if l_addr.sin6_port != r_addr.sin6_port {
                            return false
                        }
                        
                        #if os(Linux)
                            let s6_addr_len = MemoryLayout.size(ofValue: l_addr.sin6_addr.in6_u.u6_addr8)
                            let l_s6_addr = UnsafeBufferPointer(start: &l_addr.sin6_addr.in6_u.u6_addr8.0, count: s6_addr_len)
                            let r_s6_addr = UnsafeBufferPointer(start: &r_addr.sin6_addr.in6_u.u6_addr8.0, count: s6_addr_len)
                        #else
                            let s6_addr_len = MemoryLayout.size(ofValue: l_addr.sin6_addr.__u6_addr.__u6_addr8)
                            let l_s6_addr = UnsafeBufferPointer(start: &l_addr.sin6_addr.__u6_addr.__u6_addr8.0, count: s6_addr_len)
                            let r_s6_addr = UnsafeBufferPointer(start: &r_addr.sin6_addr.__u6_addr.__u6_addr8.0, count: s6_addr_len)
                        #endif
                        
                        if memcmp(l_s6_addr.baseAddress, r_s6_addr.baseAddress, s6_addr_len) != 0 {
                            return false
                        }
                    }
                case var (.unix(l_addr), .unix(r_addr)):
                    do {
                        let l_path = UnsafeBufferPointer(start: &l_addr.sun_path.0, count: MemoryLayout.size(ofValue: l_addr.sun_path))
                        let r_path = UnsafeBufferPointer(start: &r_addr.sun_path.0, count: MemoryLayout.size(ofValue: r_addr.sun_path))
                        
                        if l_path.count != r_path.count {
                            return false
                        }
                        
                        if strncmp(l_path.baseAddress, r_path.baseAddress, l_path.count) != 0 {
                            return false
                        }
                    }
                default:
                    return false
                }
            #else
                switch (lhs, rhs) {
                case let (.ipv4(l_addr), .ipv4(r_addr)):
                    do {
                        if l_addr.sin_port != r_addr.sin_port {
                            return false
                        }
                        
                        if l_addr.sin_addr.s_addr != r_addr.sin_addr.s_addr {
                            return false
                        }
                    }
                case var (.ipv6(l_addr), .ipv6(r_addr)):
                    do {
                        if l_addr.sin6_port != r_addr.sin6_port {
                            return false
                        }
                        
                        
                        let s6_addr_len = MemoryLayout.size(ofValue: l_addr.sin6_addr.u.Byte)
                        let l_s6_addr = UnsafeBufferPointer(start: &l_addr.sin6_addr.u.Byte.0, count: s6_addr_len)
                        let r_s6_addr = UnsafeBufferPointer(start: &r_addr.sin6_addr.u.Byte.0, count: s6_addr_len)
                        
                        if memcmp(l_s6_addr.baseAddress, r_s6_addr.baseAddress, s6_addr_len) != 0 {
                            return false
                        }
                    }
                default:
                    return false
                }
            #endif
            
            return true
        }
        
    }
    
    public struct Socket: RawRepresentable {
        
        #if os(Windows)
        public typealias RawValue = SOCKET
        #else
        public typealias RawValue = Int32
        #endif
        
        private var _socket: Socket.RawValue
        
        private static func _initializeSockets() -> Bool {
            #if os(Windows)
                var wsa = WSAData()
                
                guard WSAStartup(MAKEWORD(2, 0), UnsafeMutablePointer(&wsa)) != 0 else {
                    return false
                }
            #endif
            
            return true
        }
        
        private static var _initialized = Socket._initializeSockets()
        
        public var rawValue: Socket.RawValue {
            return _socket
        }
        
        public init?(rawValue: Socket.RawValue) {
            guard Socket._initialized, rawValue != Socket.RawValue(-1) else {
                return nil
            }
            
            _socket = rawValue
        }
        
        public init?(family: StreamSocket.SocketProtocolFamily, type: StreamSocket.SocketType, `protocol` _protocol: StreamSocket.SocketProtocol) {
            self.init(rawValue: socket(family.rawValue, type.rawValue | SOCK_CLOEXEC, _protocol.rawValue))
        }
    }
    
    internal var _socket: StreamSocket.Socket!
    internal var _atEndOfStream: Bool = false
    
    open override func lowLevelIsAtEndOfStream() throws -> Bool {
        guard _socket != nil else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        return _atEndOfStream
    }
    
    open override func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        guard _socket != nil else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        var bytesWritten: Int
        
        #if os(Windows)
            guard length <= Int32.max else {
                throw StreamsKitError.outOfRange
            }
            
            let _bytesWritten = send(_socket.rawValue, buffer, Int32(length), 0)
            bytesWritten = Int(_bytesWritten)
        #else
            bytesWritten = send(_socket.rawValue, buffer, length, 0)
        #endif
        
        guard bytesWritten >= 0 else {
            throw StreamsKitError.writeFailed(stream: self, requestedLength: length, bytesWritten: 0, error: _socket_errno())
        }
        
        return bytesWritten
    }
    
    open override func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        guard _socket != nil else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        var ret: Int
        
        #if os(Windows)
            guard length <= UInt32.max else {
                throw StreamsKitError.outOfRange
            }
            
            ret = recv(_socket.rawValue, buffer, UInt32(length), 0)
        #else
            ret = recv(_socket.rawValue, buffer, length, 0)
        #endif
        
        guard ret >= 0 else {
            throw StreamsKitError.readFailed(stream: self, requestedLength: length, error: _socket_errno())
        }
        
        if ret == 0 {
            _atEndOfStream = true
        }
        
        return ret
    }
    
    open override func setBlocking(_ enable: Bool) throws {
        #if os(Windows)
            var v = u_long(newValue ? 1 : 0)
            
            guard ioctlsocket(_socket, FIONBIO, UnsafeMutablePointer(&v)) != SOCKET_ERROR else {
                throw StreamsKitError.setOptionFailed(stream: self, errNo: _socket_errno())
            }
            
            _blocking = enable
        #else
            var readImplemented = false, writeImplemented = false
            
            do {
                var readFlags = fcntl(try self.fileDescriptorForReading(), F_GETFL)
                
                guard readFlags != -1 else {
                    throw StreamsKitError.setOptionFailed(stream: self, error: _socket_errno())
                }
                
                readImplemented = true
                
                if enable {
                    readFlags &= ~O_NONBLOCK
                } else {
                    readFlags |= O_NONBLOCK
                }
                
                guard fcntl(try self.fileDescriptorForReading(), F_SETFL, readFlags) != -1 else {
                    throw StreamsKitError.setOptionFailed(stream: self, error: _socket_errno())
                }
                
            } catch let error as NSError {
                if error.domain != StreamsKitErrorDomain || error.code != kPOSIXErrorENOSYS {
                    throw error
                }
            }
            
            do {
                var writeFlags = fcntl(try self.fileDescriptorForWriting(), F_GETFL)
                
                writeImplemented = true
                
                guard writeFlags != -1 else {
                    throw StreamsKitError.setOptionFailed(stream: self, error: _socket_errno())
                }
                
                if enable {
                    writeFlags &= ~O_NONBLOCK
                } else {
                    writeFlags |= O_NONBLOCK
                }
                
                guard fcntl(try self.fileDescriptorForWriting(), F_SETFL, UnsafeMutablePointer(&writeFlags)) != -1 else {
                    throw StreamsKitError.setOptionFailed(stream: self, error: _socket_errno())
                }
                
            } catch let error as NSError {
                if error.domain != StreamsKitErrorDomain || error.code != kPOSIXErrorENOSYS {
                    throw error
                }
            }
            
            guard readImplemented || writeImplemented else {
                throw StreamsKitError.notImplemented(method: #function, inStream: type(of: self))
            }
            
            _blocking = enable
        #endif
    }
    
    open override func close() throws {
        guard _socket != nil else {
            throw StreamsKitError.notOpen(stream: self)
        }
        
        CloseSocket(_socket)
        _socket = nil
        _atEndOfStream = false
        
        try super.close()
    }
    
    deinit {
        if _socket != nil {
            try! self.close()
        }
    }
}
