//
//  Errors.swift
//  StreamsKit
//
//  Created by Yury Vovk on 16.05.2018.
//

import Foundation

public let OFExceptionDomain: String = "OFExceptionDomain"

public let RequestedLengthKey: String = "RequestedLengthKey"
public let BytesWritenKey: String = "BytesWritenKey"
public let OpenPathKey: String = "OpenPathKey"
public let OpenModeKey: String = "OpenModeKey"
public let SeekOffsetKey: String = "SeekOffsetKey"
public let SeekWhenceKey: String = "SeekWhenceKey"
public let StreamKey: String = "StreamKey"
public let HostKey: String = "HostKey"
public let PortKey: String = "PortKey"
public let BacklogKey: String = "BacklogKey"

fileprivate func OFPOSIXError(_ errorCode: POSIXErrorCode, userInfo info: [String: Any]? = nil) -> NSError {
    return NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode.rawValue), userInfo: info)
}

fileprivate func OFPOSIXError(_ errorCode: Int32, userInfo info: [String: Any]? = nil) -> NSError {
    if errorCode == 0 {
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: info)
    }
    return OFPOSIXError(POSIXErrorCode(rawValue: errorCode)!, userInfo: info)
}


public enum OFException {
    public static func notImplemented<T>(method: String, inStream streamType: T.Type) -> NSError where T: OFStream {
        return NSError(domain: OFExceptionDomain, code: Int(ENOSYS), userInfo: [NSLocalizedDescriptionKey: "Method \(method) of \(String(describing: streamType)) is not implemented"])
    }
    
    public static func outOfRange() -> NSError {
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Value out of range"])
    }
    
    public static func notOpen<T>(stream: T, userInfo info: [String: Any]? = nil) -> NSError where T: OFStream {
        var _userInfo = [String: Any]()
        
        if let info = info {
            _userInfo.merge(info, uniquingKeysWith: {_, x in x})
        }
        
        _userInfo[NSLocalizedDescriptionKey] = "The stream of type \(String(describing: stream)) is not open, connected or bound"
        _userInfo[StreamKey] = stream
        
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: _userInfo)
    }
    
    public static func notOpen<T>(stream: T, userInfo info: [String: Any]? = nil) -> NSError where T: StreamsKit.UDPSocket {
        var _userInfo = [String: Any]()
        
        if let info = info {
            _userInfo.merge(info, uniquingKeysWith: {_, x in x})
        }
        
        _userInfo[NSLocalizedDescriptionKey] = "The stream of type \(String(describing: stream)) is not open, connected or bound"
        _userInfo[StreamKey] = stream
        
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: _userInfo)
    }
    
    public static func alreadyConnected<T>(stream: T, userInfo info: [String: Any]? = nil) -> NSError where T: StreamsKit.TCPSocket {
        var _userInfo = [String: Any]()
        
        if let info = info {
            _userInfo.merge(info, uniquingKeysWith: {_, x in x})
        }
        
        _userInfo[NSLocalizedDescriptionKey] = "The stream of type \(String(describing: stream)) is already connected or bound and thus can't be connected or bound again!"
        _userInfo[StreamKey] = stream
        
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: _userInfo)
    }
    
    public static func alreadyConnected<T>(stream: T, userInfo info: [String: Any]? = nil) -> NSError where T: StreamsKit.UDPSocket {
        var _userInfo = [String: Any]()
        
        if let info = info {
            _userInfo.merge(info, uniquingKeysWith: {_, x in x})
        }
        
        _userInfo[NSLocalizedDescriptionKey] = "The stream of type \(String(describing: stream)) is already connected or bound and thus can't be connected or bound again!"
        _userInfo[StreamKey] = stream
        
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: _userInfo)
    }
    
    public static func bindFailed<T>(host: String, port: UInt16, socket: T, error: Int32) -> NSError where T: StreamsKit.TCPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: socket,
            HostKey: host,
            PortKey: port
            ])
    }
    
    public static func bindFailed<T>(host: String, port: UInt16, socket: T, error: Int32) -> NSError where T: StreamsKit.UDPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: socket,
            HostKey: host,
            PortKey: port
            ])
    }
    
    public static func listenFailed<T>(socket: T, backlog: Int, error: Int32) -> NSError where T: StreamsKit.TCPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: socket,
            BacklogKey: backlog
            ])
    }
    
    public static func connectionFailed<T>(host: String, port: UInt16, socket: T, error: Int32) -> NSError where T: StreamsKit.TCPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: socket,
            HostKey: host,
            PortKey: port
            ])
    }
    
    public static func writeFailed<T>(stream: T, requestedLength: Int, bytesWritten: Int, error: Int32) -> NSError where T: OFStream {
        return OFPOSIXError(error, userInfo: [
            StreamKey: stream,
            RequestedLengthKey: requestedLength,
            BytesWritenKey: bytesWritten
            ])
    }
    
    public static func writeFailed<T>(stream: T, requestedLength: Int, bytesWritten: Int, error: Int32) -> NSError where T: StreamsKit.UDPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: stream,
            RequestedLengthKey: requestedLength,
            BytesWritenKey: bytesWritten
            ])
    }
    
    public static func readFailed<T>(stream: T, requestedLength: Int, error: Int32) -> NSError where T: OFStream {
        return OFPOSIXError(error, userInfo: [
            StreamKey: stream,
            RequestedLengthKey: requestedLength
            ])
    }
    
    public static func readFailed<T>(stream: T, requestedLength: Int, error: Int32) -> NSError where T: StreamsKit.UDPSocket {
        return OFPOSIXError(error, userInfo: [
            StreamKey: stream,
            RequestedLengthKey: requestedLength
            ])
    }
    
    public static func setOptionFailed<T>(stream: T, error: Int32) -> NSError where T: OFStreamSocket {
        return OFPOSIXError(error, userInfo: [StreamKey: stream])
    }
    
    public static func getOptionFailed<T>(stream: T, error: Int32) -> NSError where T: OFStreamSocket {
        return OFPOSIXError(error, userInfo: [StreamKey: stream])
    }
    
    public static func openFailed(path: String, mode: String, error: Int32) -> NSError {
        return OFPOSIXError(error, userInfo: [OpenPathKey: path, OpenModeKey: mode])
    }
    
    public static func seekFailed<T>(stream: T, offset: OFSeekableStream.offset_t, whence: Int32, error: Int32) -> NSError where T: OFSeekableStream {
        return OFPOSIXError(error, userInfo: [StreamKey: stream, SeekOffsetKey: offset, SeekWhenceKey: whence])
    }
    
    public static func addressTranslationFailed(host: String, error: Int32) -> NSError {
        return OFPOSIXError(errno, userInfo: [HostKey: host])
    }
    
    public static func acceptFailed<T>(socket: T, error: Int32) -> NSError where T: StreamsKit.TCPSocket {
        return OFPOSIXError(error, userInfo: [StreamKey: socket])
    }
    
    public static func truncatedData() -> NSError {
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: ""])
    }
    
    public static func invalidArgument() -> NSError {
        return NSError(domain: OFExceptionDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: ""])
    }
}
