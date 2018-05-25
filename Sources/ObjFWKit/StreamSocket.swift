//
//  OFStreamSocket.swift
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

open class OFStreamSocket: OFStream, OFReadyForReadingObserving, OFReadyForWritingObserving {
    
    
    
    internal var _socket: Socket!
    internal var _atEndOfStream: Bool = false
    
    open var sourceForReading: CFRunLoopSource {
        return _socket.runLoopSource
    }
    
    open var sourceForWriting: CFRunLoopSource {
        return _socket.runLoopSource
    }
    
    open override func lowLevelIsAtEndOfStream() throws -> Bool {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        return _atEndOfStream
    }
    
    open override func lowLevelWrite(_ buffer: UnsafeRawPointer, length: Int) throws -> Int {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        var bytesWritten: Int
        
        #if os(Windows)
            guard length <= Int32.max else {
                throw OFException.outOfRange
            }
            
            let _bytesWritten = send(_socket.rawValue, buffer, Int32(length), 0)
            bytesWritten = Int(_bytesWritten)
        #else
            bytesWritten = send(_socket.rawValue, buffer, length, 0)
        #endif
        
        guard bytesWritten >= 0 else {
            throw OFException.writeFailed(stream: self, requestedLength: length, bytesWritten: 0, error: _socket_errno())
        }
        
        return bytesWritten
    }
    
    open override func lowLevelRead(into buffer: inout UnsafeMutableRawPointer, length: Int) throws -> Int {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        var ret: Int
        
        #if os(Windows)
            guard length <= UInt32.max else {
                throw OFException.outOfRange
            }
            
            ret = recv(_socket.rawValue, buffer, UInt32(length), 0)
        #else
            ret = recv(_socket.rawValue, buffer, length, 0)
        #endif
        
        guard ret >= 0 else {
            throw OFException.readFailed(stream: self, requestedLength: length, error: _socket_errno())
        }
        
        if ret == 0 {
            _atEndOfStream = true
        }
        
        return ret
    }
    
    open override func setBlocking(_ enable: Bool) throws {
        #if os(Windows)
            var v = u_long(newValue ? 1 : 0)
            
            guard ioctlsocket(_socket.rawValue, FIONBIO, UnsafeMutablePointer(&v)) != SOCKET_ERROR else {
                throw OFException.setOptionFailed(stream: self, errNo: _socket_errno())
            }
            
            _blocking = enable
        #else
            
            var readFlags = fcntl(_socket.rawValue, F_GETFL)
            
            guard readFlags != -1 else {
                throw OFException.setOptionFailed(stream: self, error: _socket_errno())
            }
            
            if enable {
                readFlags &= ~O_NONBLOCK
            } else {
                readFlags |= O_NONBLOCK
            }
            
            guard fcntl(_socket.rawValue, F_SETFL, readFlags) != -1 else {
                throw OFException.setOptionFailed(stream: self, error: _socket_errno())
            }
        #endif
        
        _blocking = enable
    }
    
    open override func close() throws {
        guard _socket != nil else {
            throw OFException.notOpen(stream: self)
        }
        
        CloseSocket(_socket)
        _socket = nil
        _atEndOfStream = false
        
        try super.close()
    }
    
    open override func cancelAsyncRequests() {
        _socket.invalidate()
        super.cancelAsyncRequests()
    }
    
    deinit {
        if _socket != nil {
            try! self.close()
        }
    }
}
