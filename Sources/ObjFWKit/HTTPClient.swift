//
//  HTTPClient.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 23.05.2018.
//

import Foundation

public protocol OFHTTPClientDelegate: class {
    func client(_ client: OFHTTPClient, didPerformRequest request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) -> Swift.Void
    
    func clien(_ client: OFHTTPClient, didEncounterError error: Error, request: OFHTTPRequest, context: AnyObject?) -> Swift.Void
    
    func client(_ client: OFHTTPClient, didCreateSocket socket: OFTCPSocket, request: OFHTTPRequest, context: AnyObject?) -> Swift.Void
    
    func client(_ client: OFHTTPClient, wantsRequestBody requestBody: OFStream, request: OFHTTPRequest, context: AnyObject?) -> Swift.Void
    
    func client(_ client: OFHTTPClient, didReceiveHeaders headers: [String: String], statusCode: Int, request: OFHTTPRequest, context: AnyObject?) -> Swift.Void
    
    func client(_ client: OFHTTPClient, shouldFollowRedirect redirectURL: URL, statusCode: Int, request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) -> Bool
}

fileprivate func defaultShouldFollow(_ method: OFHTTPRequestMethod, _ code: Int) -> Bool {
    var follow: Bool
    
    if method == .GET || method == .HEAD {
        follow = true
    } else if code == 303 {
        follow = true
    } else {
        follow = false
    }
    
    return follow
}

public extension OFHTTPClientDelegate {
    public func client(_ client: OFHTTPClient, didCreateSocket socket: OFTCPSocket, request: OFHTTPRequest, context: AnyObject?) {}
    
    public func client(_ client: OFHTTPClient, wantsRequestBody requestBody: OFStream, request: OFHTTPRequest, context: AnyObject?) {}
    
    public func client(_ client: OFHTTPClient, didReceiveHeaders headers: [String: String], statusCode: Int, request: OFHTTPRequest, context: AnyObject?) {
        
    }
    
    public func client(_ client: OFHTTPClient, shouldFollowRedirect redirectURL: URL, statusCode: Int, request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) -> Bool {
        
        return defaultShouldFollow(request.method, statusCode)
    }
}

open class OFHTTPClient {
    open weak var delegate: OFHTTPClientDelegate?
    
    open var insecureRedirectsAllowed: Bool = false
    
    internal var _socket: OFTCPSocket!
    
    internal var _lastURL: URL!
    
    internal var _lastWasHEAD: Bool = false
    
    internal var _inProgress: Bool = false
    
    internal var _lastResponse: OFHTTPResponse!
    
    open func performRequest(_ request: OFHTTPRequest, redirects: UInt = 10, context: AnyObject? = nil) -> (response: OFHTTPResponse?, error: Error?) {
        
        let syncPerformer = OFHTTPClient_SyncPerformer(withClient: self)
        
        return syncPerformer.performRequest(request, redirects: redirects, context: context)
    }
    
    open func asyncPerformRequest(_ request: OFHTTPRequest, redirects: UInt = 10, context: AnyObject? = nil) throws {
        guard let scheme = request.URL.scheme else {
            throw OFException.invalidArgument()
        }
        
        guard scheme == "http" || scheme == "https" else {
            throw OFException.unsupportedProtocol(request.URL)
        }
        
        guard !_inProgress else {
            throw OFException.alreadyConnected(stream: _socket)
        }
        
        _inProgress = true
        
        let handler = OFHTTPClientRequestHandler(withClient: self, request: request, redirects: redirects, context: context)
        
        try handler.start()
    }
    
    open func close() {
        
    }
    
    deinit {
        self.close()
    }
}

fileprivate class OFHTTPClient_SyncPerformer: OFHTTPClientDelegate {
    private weak var _delegate: OFHTTPClientDelegate?
    private var _client: OFHTTPClient
    private var _response: OFHTTPResponse!
    private var _error: Error!
    
    init(withClient client: OFHTTPClient) {
        _client = client
        _delegate = _client.delegate
        _client.delegate = self
    }
    
    func performRequest(_ request: OFHTTPRequest, redirects: UInt, context: AnyObject?) -> (response: OFHTTPResponse?, error: Error?) {
        
        do {
            try _client.asyncPerformRequest(request, redirects: redirects, context: context)
            
            RunLoop.current.run()
        } catch {
            _error = error
        }
        
        return (_response, _error)
    }
    
    func client(_ client: OFHTTPClient, didPerformRequest request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) {
        
        CFRunLoopStop(RunLoop.current.getCFRunLoop())
        
        _response = nil
        _response = response
        
        _delegate?.client(client, didPerformRequest: request, response: response, context: context)
    }
    
    func clien(_ client: OFHTTPClient, didEncounterError error: Error, request: OFHTTPRequest, context: AnyObject?) {
        
        CFRunLoopStop(RunLoop.current.getCFRunLoop())
        
        _client.delegate = _delegate
        _error = error
    }
    
    public func client(_ client: OFHTTPClient, didCreateSocket socket: OFTCPSocket, request: OFHTTPRequest, context: AnyObject?) {
        _delegate?.client(client, didCreateSocket: socket, request: request, context: context)
    }
    
    public func client(_ client: OFHTTPClient, wantsRequestBody requestBody: OFStream, request: OFHTTPRequest, context: AnyObject?) {
        _delegate?.client(client, wantsRequestBody: requestBody, request: request, context: context)
    }
    
    public func client(_ client: OFHTTPClient, didReceiveHeaders headers: [String: String], statusCode: Int, request: OFHTTPRequest, context: AnyObject?) {
        _delegate?.client(client, didReceiveHeaders: headers, statusCode: statusCode, request: request, context: context)
    }
    
    public func client(_ client: OFHTTPClient, shouldFollowRedirect redirectURL: URL, statusCode: Int, request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) -> Bool {
        
        return _delegate?.client(client, shouldFollowRedirect: redirectURL, statusCode: statusCode, request: request, response: response, context: context) ?? true
    }
    
    deinit {
        _client.delegate = _delegate
    }
}

fileprivate func constructRequestString(_ request: OFHTTPRequest) throws -> String {
    guard let components = URLComponents(url: request.URL, resolvingAgainstBaseURL: true) else {
        throw OFException.badURL(request.URL)
    }
}

fileprivate func normalizeKey(_ key: String) -> String {
    
}

fileprivate class OFHTTPClientRequestHandler {
    var _client: OFHTTPClient
    var _request: OFHTTPRequest
    var _redirects: UInt
    var _context: AnyObject?
    var _firstLine: Bool = false
    var _version: String!
    var _status: Int = 0
    var _serverHeaders = [String: String]()
    
    
    init(withClient client: OFHTTPClient, request: OFHTTPRequest, redirects: UInt, context: AnyObject?) {
        _client = client
        _request = request
        _redirects = redirects
        _context = context
    }
    
    func start() throws {
        var socket: OFTCPSocket
        
        if let lastScheme = _client._lastURL.scheme, let requstScheme = _request.URL.scheme, let lastHost = _client._lastURL.host, let requestHost = _request.URL.host, let lastPort = _client._lastURL.port, let requestPort = _request.URL.port, _client._socket != nil && !((try? _client._socket.atEndOfStream()) ?? true) && lastScheme == requstScheme && lastHost == requestHost && lastPort == requestPort {
            
            socket = _client._socket
            _client._socket = nil
            _client._lastURL = nil
            
            let lastResponseAtEndOfStream = try _client._lastResponse.atEndOfStream()
            
            if !_client._lastWasHEAD && !lastResponseAtEndOfStream {
                
                var buffer = UnsafeMutableRawPointer.allocate(bytes: 512, alignedTo: MemoryLayout<UInt8>.alignment)
                
                _client._lastResponse.asyncRead(into: &buffer, length: 512) {
                    return self.throwAwayContent(response: $0 as! OFHTTPClientResponse, buffer: $1, length: $2, socket:socket, error: $3)
                }
                
            } else {
                _client._lastResponse = nil
                RunLoop.current.execute {
                    self.handleSocket(socket)
                }
            }
            
        } else {
            self.closeAndReconnect()
        }
    }
    
    func closeAndReconnect() {
        do {
            var sock: OFTCPSocket
            var port: UInt16
            
            _client.close()
            
            guard let host = _request.URL.host else {
                throw OFException.badURL(_request.URL)
            }
            
            if _request.URL.scheme! == "https" {
                throw OFException.unsupportedProtocol(_request.URL)
            } else {
                sock = OFTCPSocket()
                port = 80
            }
            
            if let URLPort = _request.URL.port {
                port = UInt16(truncatingIfNeeded: URLPort)
            }
            
            sock.asyncConnectToHost(host, port: port) {
                if let error = $1 {
                    self.raiseError(error)
                    return
                }
                
                self._client.delegate?.client(self._client, didCreateSocket: sock, request: self._request, context: self._context)
                
                RunLoop.current.execute {
                    self.handleSocket(sock)
                }
            }
            
        } catch {
            self.raiseError(error)
        }
    }
    
    func raiseError(_ error: Error) {
        _client.close()
        _client._inProgress = false
        
        _client.delegate?.clien(_client, didEncounterError: error, request: _request, context: _context)
    }
    
    func createResponseWithSocketOrThrow(_ socket: OFTCPSocket) throws {
        let response = OFHTTPClientResponse(withSocket: socket)
        
        response.protocolVersion = OFHTTPRequestProtocolVersion(fromString: _version)!
        response.statusCode = UInt16(truncatingIfNeeded: _status)
        response.headers = _serverHeaders
        
        let connectionHeader = _serverHeaders["Connection"]
        
        var keepAlive: Bool
        
        if _version == "1.1" {
            if connectionHeader != nil {
                keepAlive = connectionHeader!.caseInsensitiveCompare("close") != .orderedSame
            } else {
                keepAlive = true
            }
        } else {
            if connectionHeader != nil {
                keepAlive = connectionHeader?.caseInsensitiveCompare("keep-alive") == .orderedSame
            } else {
                keepAlive = false
            }
        }
        
        if keepAlive {
            response.of_keepAlive = true
            _client._socket = socket
            _client._lastURL = _request.URL
            _client._lastWasHEAD = _request.method == .HEAD
            _client._lastResponse = response
        }
        var location: String?
        
        if _redirects > 0 && (_status == 301 || _status == 301 || _status == 303 || _status == 307) && (location = _serverHeaders["Location"], location).1 != nil && (_client.insecureRedirectsAllowed || _request.URL.scheme! == "http" || location!.hasPrefix("https://")) {
            
            guard let newURL = URL(string: location!, relativeTo: _request.URL) else {
                throw OFException.invalidServerReply()
            }
            
            var follow: Bool
            
            if _client.delegate != nil {
                follow = _client.delegate!.client(_client, shouldFollowRedirect: newURL, statusCode: _status, request: _request, response: response, context: _context)
            } else {
                follow = defaultShouldFollow(_request.method, _status)
            }
            
            if follow {
                let newRequest = OFHTTPRequest(_request)
                
                if let newHost = newURL.host, let oldHost = _request.URL.host, newHost != oldHost {
                    newRequest.headers?.removeValue(forKey: "Host")
                }
                
                if _status == 303 {
                    if let headers = _request.headers {
                        for (key, _) in headers {
                            if key.hasPrefix("Content-") || key.hasPrefix("Transfer-") {
                                newRequest.headers?.removeValue(forKey: key)
                            }
                        }
                    }
                    
                    newRequest.method = .GET
                }
                
                newRequest.URL = newURL
                _client._inProgress = false
                
                try _client.asyncPerformRequest(newRequest, redirects: _redirects - 1, context: _context)
            }
        }
        
        _client._inProgress = false
        
        guard _status / 100 == 2 else {
            throw OFException.requestFailed(_request, response: response)
        }
        
        let client = _client
        let request = _request
        let context = _context
        
        RunLoop.current.execute {
            client.delegate?.client(client, didPerformRequest: request, response: response, context: context)
        }
    }
    
    func createResponseWithSocket(_ socket: OFTCPSocket) {
        do {
            try self.createResponseWithSocketOrThrow(socket)
        } catch {
            self.raiseError(error)
        }
    }
    
    func handleFirstLine(_ line: String?) throws -> Bool {
        guard let line = line else {
            self.closeAndReconnect()
            return false
        }
        
        guard line.hasPrefix("HTTP/") && line.count >= 9 else {
            throw OFException.invalidServerReply()
        }
        
        var index = line.index(line.startIndex, offsetBy: 8)
        
        guard line[index] == " " else {
            throw OFException.invalidServerReply()
        }
        
        index = line.index(line.startIndex, offsetBy: 5)
        var end = line.index(index, offsetBy: 3)
        
        _version = String(line[index..<end])
        
        guard _version == "1.0" || _version == "1.1" else {
            throw OFException.unsupportedVersion(_version)
        }
        
        index = line.index(line.startIndex, offsetBy: 9)
        end = line.index(index, offsetBy: 3)
        
        if let status = Int(line[index..<end]) {
            _status = status
        }
        
        return true
    }
    
    func handleServerHeader(_ header: String?, socket: OFTCPSocket) throws -> Bool {
        guard let header = header else {
            throw OFException.invalidServerReply()
        }
        
        if header.count == 0 {
            _client.delegate?.client(_client, didReceiveHeaders: _serverHeaders, statusCode: _status, request: _request, context: _context)
            
            RunLoop.current.execute {
                self.createResponseWithSocket(socket)
            }
            
            return false
        }
        
        guard var tmp = header.index(of: ":") else {
            throw OFException.invalidArgument()
        }
        
        var key = String(header[header.startIndex..<tmp])
        
        key = normalizeKey(key)
        
        repeat {
            tmp = header.index(after: tmp)
        } while header[tmp] == " "
        
        var value = String(header[tmp...header.endIndex])
        
        if let old = _serverHeaders[key] {
            value = old + "," + value
        }
        
        _serverHeaders[key] = value
        
        return true
    }
    
    func socke(_ socket: OFTCPSocket, didReadLine line: String?, error: Error?) -> Bool {
        var ret: Bool
        
        if let error = error {
            self.raiseError(error)
            
            return false
        }
        
        do {
            if _firstLine {
                _firstLine = false
                ret = try self.handleFirstLine(line)
            } else {
                ret = try self.handleServerHeader(line, socket: socket)
            }
        } catch {
            self.raiseError(error)
            ret = false
        }
        
        return ret
    }
    
    func handleSocket(_ socket: OFTCPSocket) {
        do {
            
            let requestString = try constructRequestString(_request)
            let UTF8StringLength = requestString.lengthOfBytes(using: .utf8)
            var UTF8String = UnsafeMutableRawBufferPointer.allocate(count: UTF8StringLength)
            
            requestString.withCString {
                let buffer = UnsafeRawPointer($0)
                UTF8String.baseAddress!.copyBytes(from: buffer, count: UTF8StringLength)
            }
            
            socket.asyncWrite(buffer: UTF8String.baseAddress!, length: UTF8StringLength) {
                defer {
                    UTF8String.deallocate()
                }
                
                if let error = $3 {
                    let _error = error as NSError
                    if _error.code == Int(POSIXError.ECONNRESET.rawValue) || _error.code == Int(POSIXError.EPIPE.rawValue) {
                        
                        self.closeAndReconnect()
                        return 0
                    }
                    
                    self.raiseError(error)
                    return 0
                }
                
                self._firstLine = true
                
                if self._request.headers?["Content-Length"] != nil {
                    
                    do {
                        let requestBody = try OFHTTPClientRequestBodyStream(withHandler: self, socket: $0 as! OFTCPSocket)
                        
                        self._client.delegate?.client(self._client, wantsRequestBody: requestBody, request: self._request, context: self._context)
                    } catch {
                        self.raiseError(error)
                    }
                    
                } else {
                    socket.asyncReadLine {
                        return self.socke($0 as! OFTCPSocket, didReadLine: $1, error: $2)
                    }
                }
                
                return 0
            }
            
        } catch {
            self.raiseError(error)
            return
        }
    }
    
    func throwAwayContent(response: OFHTTPClientResponse, buffer: UnsafeMutableRawPointer, length: Int, socket: OFTCPSocket, error: Error?) -> Bool {
        
        if let error = error {
            self.raiseError(error)
            return false
            
        } else {
            do {
                let responseAtEndOfStream = try response.atEndOfStream()
                
                if responseAtEndOfStream {
                    buffer.deallocate(bytes: 512, alignedTo: MemoryLayout<UInt8>.alignment)
                    _client._lastResponse = nil
                    
                    RunLoop.current.execute {
                        self.handleSocket(socket)
                    }
                    
                    return false
                }
                
            } catch {
                _client._lastResponse = nil
                self.closeAndReconnect()
                return false
            }
        }
        
        return true
    }
}

fileprivate class OFHTTPClientRequestBodyStream: OFStream {
    var _handler: OFHTTPClientRequestHandler
    var _socket: OFTCPSocket
    var _toWrite: Int = 0
    var _atEndOfStream: Bool = false
    
    init(withHandler handler: OFHTTPClientRequestHandler, socket: OFTCPSocket) throws {
        _handler = handler
        _socket = socket
        
        guard let headers = _handler._request.headers, let contentLengthString = headers["Content-Length"], let contentLength = Int(contentLengthString), contentLength >= 0 else {
            throw OFException.invalidArgument()
        }
        
        _toWrite = contentLength
        
        guard headers["Transfer-Encoding"] == nil else {
            throw OFException.invalidArgument()
        }
    }
}

fileprivate class OFHTTPClientResponse: OFHTTPResponse {
    private var _socket: OFTCPSocket
    private var _hasContentLength: Bool = false
    private var _chanked: Bool = false
    var of_keepAlive: Bool = false
    private var _atEndOfStream: Bool = false
    private var _toRead: Int = 0
    
    override var headers: [String : String] {
        get {
            return super.headers
        }
        
        set {
            super.headers = newValue
            
            if let chanked = self.headers["Transfer-Encoding"] {
                _chanked = chanked == "chunked"
            }
            
            if let contentLength = self.headers["Content-Length"] {
                _hasContentLength = true
                
                _toRead = Int(contentLength) ?? 0
            }
        }
    }
    
    init(withSocket socket: OFTCPSocket) {
        _socket = socket
    }
}