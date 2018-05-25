//
//  main.swift
//  test
//
//  Created by Yury Vovk on 24.05.2018.
//

import Foundation
import ObjFWKit

class Delegate: OFHTTPClientDelegate {
    func client(_ client: OFHTTPClient, didPerformRequest request: OFHTTPRequest, response: OFHTTPResponse, context: AnyObject?) {
        print("performed")
    }
    
    func clien(_ client: OFHTTPClient, didEncounterError error: Error, request: OFHTTPRequest, context: AnyObject?) {
        print(error)
    }
    
    
}

let request = OFHTTPRequest(withURL: URL(string: "http://google.com")!)

let client = OFHTTPClient()
let delegate = Delegate()

client.delegate = delegate

let (response, error) = client.performRequest(request, redirects: 0)

/*
let sock = OFTCPSocket()

sock.asyncConnectToHost("google.ru", port: 80) {_, _ in
    let request = "GET / HTTP/1.1\r\nHost: google.com\r\n\r\n"
    
    do {
        try request.withCString {
            try sock.write(buffer: $0, length: request.lengthOfBytes(using: .utf8))
        }
        
        sock.asyncReadLine {
            if let error = $2 {
                print(error)
                return false
            }
            
            if let line = $1 {
                
                var _line: String? = line
                
                while _line != nil && !_line!.isEmpty {
                    print(_line!)
                    
                    do {
                        _line = try sock.readLine()
                    } catch {
                        print("error")
                        return false
                    }
                }
                
                return true
            }
            
            return false
        }
    } catch {
        print(error)
    }
}

RunLoop.main.run()
*/
