//
//  Socket.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 25.05.2018.
//

import Foundation

public func CloseSocket(_ socket: Socket) {
    #if os(Windows)
        closesocket(socket.rawValue)
    #else
        close(socket.rawValue)
    #endif
}

public func AcceptSocket(_ socket: Socket) -> (acceptedSocket: Socket?, acceptedSocketAddress: SocketAddress) {
    let address = SocketAddress()
    
    let rawSocket = address.withSockAddrPointer {(addr, len) -> Socket.RawValue in
        var _len = len
        return withUnsafeMutablePointer(to: &_len) {
            return accept(socket.rawValue, addr, $0)
        }
    }
    
    return (Socket(rawValue: rawSocket), address)
}

public func ListenOnSocket(_ socket: Socket, withBacklog backlog: Int) -> Bool {
    return listen(socket.rawValue, Int32(backlog)) != -1
}

public func BindSocket(_ socket: Socket, onAddress address: SocketAddress) -> Bool {
    return address.withSockAddrPointer {
        return bind(socket.rawValue, $0, $1) == 0
    }
}

public func ConnectSocket(_ socket: Socket, toAddress address: SocketAddress) -> Bool {
    return address.withSockAddrPointer {
        return connect(socket.rawValue, $0, $1) != -1
    }
}

fileprivate func processSocketEvents(_ socketObject: CFSocket?, _ callbackType: CFSocketCallBackType, _ address: CFData?, _ data: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) -> Swift.Void {
    
    guard let info = info else {
        preconditionFailure("Missing socket context pointer!")
    }
    
    let unmanaged = Unmanaged<Socket>.fromOpaque(info).takeUnretainedValue()
    
    if callbackType.contains(.readCallBack) {
        StreamObserver.current.sourceReadyForReading(unmanaged.runLoopSource)
    }
    
    if callbackType.contains(.writeCallBack) {
        StreamObserver.current.sourceReadyForWriting(unmanaged.runLoopSource)
    }
}

public final class Socket: RawRepresentable, Hashable {
    
    public typealias RawValue = CFSocketNativeHandle
    
    private var _socket: CFSocket!
    
    private static func _initializeSockets() -> Bool {
        #if os(Windows)
            var wsa = WSAData()
            
            guard WSAStartup(MAKEWORD(2, 0), UnsafeMutablePointer(&wsa)) != 0 else {
                return false
            }
        #endif
        
        return true
    }
    
    public var hashValue: Int {
        return _socket.hashValue
    }
    
    #if os(Windows)
    public static var INVALID_SOCKET: Socket.RawValue = Socket.RawValue(bitPattern: Int(-1))
    #else
    public static var INVALID_SOCKET: Socket.RawValue = Socket.RawValue(-1)
    #endif
    
    private static var _initialized = Socket._initializeSockets()
    
    public lazy var runLoopSource: CFRunLoopSource = {
        return CFSocketCreateRunLoopSource(nil, _socket, 0)
    }()
    
    public var rawValue: Socket.RawValue {
        return CFSocketGetNative(_socket)
    }
    
    public required init?(rawValue: Socket.RawValue) {
        guard Socket._initialized && rawValue != Socket.INVALID_SOCKET else {
            return nil
        }
        
        let unmanaged = Unmanaged.passUnretained(self)
        var context = CFSocketContext(version: 0, info: unmanaged.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callbackType: CFSocketCallBackType = [.readCallBack, .writeCallBack]
        
        _socket = CFSocketCreateWithNative(nil, rawValue, callbackType.rawValue, processSocketEvents, &context)
        
        guard _socket != nil else {
            return nil
        }
        
        var flags = self.getSocketFlags()
        
        flags &= ~kCFSocketCloseOnInvalidate
        flags |= (kCFSocketLeaveErrors | kCFSocketAutomaticallyReenableReadCallBack | kCFSocketAutomaticallyReenableWriteCallBack)
        
        self.setSocketFlags(flags)
    }
    
    public convenience init?(family: SocketProtocolFamily, type: SocketType, `protocol` _protocol: SocketProtocol) {
        guard Socket._initialized else {
            return nil
        }
        
        self.init(rawValue: socket(family.rawValue, type.rawValue | SOCK_CLOEXEC, _protocol.rawValue))
    }
    
    public func invalidate() {
        CFSocketInvalidate(_socket)
    }
    
    public func getSocketFlags() -> CFOptionFlags {
        return CFSocketGetSocketFlags(_socket)
    }
    
    public func setSocketFlags(_ v: CFOptionFlags) {
        CFSocketSetSocketFlags(_socket, v)
    }
    
    public func enableCallBacks(_ type: CFSocketCallBackType) {
        CFSocketEnableCallBacks(_socket, type.rawValue)
    }
    
    public func disableCallBacks(_ type: CFSocketCallBackType) {
        CFSocketDisableCallBacks(_socket, type.rawValue)
    }
    
    public func localAddress() -> SocketAddress? {
        guard let addressData = CFSocketCopyAddress(_socket) else {
            return nil
        }
        
        guard let addr = UnsafeMutableRawPointer(mutating: CFDataGetBytePtr(addressData)) else {
            return nil
        }
        
        return SocketAddress(addr.bindMemory(to: sockaddr.self, capacity: 1))
    }
    
    public func peerAddress() -> SocketAddress? {
        guard let addressData = CFSocketCopyPeerAddress(_socket) else {
            return nil
        }
        
        guard let addr = UnsafeMutableRawPointer(mutating: CFDataGetBytePtr(addressData)) else {
            return nil
        }
        
        return SocketAddress(addr.bindMemory(to: sockaddr.self, capacity: 1))
    }
}

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
    
    public var family: SocketProtocolFamily? {
        switch self {
        case .ipv6(_):
            return .inet6
        case .ipv4(_):
            return .inet
        case .unix(_):
            return .unix
        case .storage(let address):
            do {
                return SocketProtocolFamily(rawValue: Int32(address.ss_family))
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
        
        guard let family = SocketProtocolFamily(rawValue: Int32(_address.pointee.sa_family)) else {
            return nil
        }
        
        #if !os(Windows)
            switch family {
            case .inet:
                self = _address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    return SocketAddress.ipv4($0.pointee)
                }
            case .inet6:
                self = _address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    return SocketAddress.ipv6($0.pointee)
                }
            case .unix:
                self = _address.withMemoryRebound(to: sockaddr_un.self, capacity: 1) {
                    return SocketAddress.unix($0.pointee)
                }
            default:
                return nil
            }
        #else
            switch family {
            case .inet:
                self = _address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    return SocketAddress.ipv4($0.pointee)
                }
            case .inet6:
                self = _address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    return SocketAddress.ipv6($0.pointee)
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
                            return SocketAddress.ipv4($0.pointee)
                        }
                    }
                case .inet6:
                    self = withUnsafeMutablePointer(to: &_address) {
                        return $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                            return SocketAddress.ipv6($0.pointee)
                        }
                    }
                case .unix:
                    self = withUnsafeMutablePointer(to: &_address) {
                        return $0.withMemoryRebound(to: sockaddr_un.self, capacity: 1) {
                            return SocketAddress.unix($0.pointee)
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
                            return SocketAddress.ipv4($0.pointee)
                        }
                    }
                case .inet6:
                    self = withUnsafeMutablePointer(to: &_address) {
                        return $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                            return SocketAddress.ipv6($0.pointee)
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
    
    public static func ==(lhs: SocketAddress, rhs: SocketAddress) -> Bool {
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
