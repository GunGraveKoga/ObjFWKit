//
//  TLSSocket.swift
//  ObjFWKit
//
//  Created by Yury Vovk on 25.05.2018.
//

import Foundation

public protocol OFTLSSocketDelegate: class {
    func socket<K, V>(_ socket: OFTLSSocket, shouldAcceptCertificate certificate: [K: V]) -> Bool
}

public protocol OFTLSSocketProtocol: class {
    weak var delegate: OFTLSSocketDelegate? {get set}
    var certificateFile: String! {get set}
    var privateKeyFile: String! {get set}
    var privateKeyPassphrase: String! {get set}
    var certificateVerificationEnabled: Bool {get set}
    
    init(withSocket socket: OFTCPSocket)
    
    func startTLSWithExpectedHost(_ host: String?) -> Swift.Void
    
    func setCertificateFile(_ file: String, forSHIHost host: String) -> Swift.Void
    
    func certificateFile(forSNIHost host: String) -> String?
    
    func setPrivateKeyFile(_ file: String, forSHIHost host: String) -> Swift.Void
    
    func privateKeyFile(forSNIHost host: String) -> String?
    
    func setPrivateKeyPassphrase(_ passphrase: String, forSHIHost host: String) -> Swift.Void
    
    func privateKeyPassphrase(forSNIHost host: String) -> String?
    
}

public typealias OFTLSSocket = OFTCPSocket & OFTLSSocketProtocol

public var OFTLSSocketClass: OFTLSSocket.Type! = nil
