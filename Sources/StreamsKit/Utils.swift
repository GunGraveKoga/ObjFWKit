//
//  Utils.swift
//  StreamsKit
//
//  Created by Yury Vovk on 17.05.2018.
//

import Foundation

#if os(macOS)
internal class __TimerContext: NSObject {
    var _block: () -> Swift.Void = {}
    
    init(block: @escaping () -> Swift.Void) {
        super.init()
        
        _block = block
    }
    
    @objc
    func executeBlock() {
        _block()
    }
}

internal class __AsyncExetutionThread: Thread {
    var _block: () -> Swift.Void = {}
    
    convenience init(withAsyncBlock block: @escaping () -> Void) {
        self.init()
        _block = block
    }
    
    override func main() {
        _block()
    }
}
    
#endif

internal extension Thread {
    class func asyncExecute(_ block: @escaping () -> Swift.Void) {
        #if os(macOS)
            if #available(OSX 10.12, *) {
                Thread.detachNewThread(block)
            } else {
                let t = __AsyncExetutionThread(withAsyncBlock: block)
                
                t.start()
            }
        #else
            Thread.detachNewThread(_block)
        #endif
    }
}

internal extension RunLoop {
    func execute(_ block: @escaping () -> Swift.Void) {
        var timer: Timer
        
        #if os(macOS)
            if #available(OSX 10.12, *) {
                timer = Timer(timeInterval: 0.0, repeats: false, block: {_ in block()})
            } else {
                let ctx = __TimerContext(block: block)
                timer = Timer(timeInterval: 0.0, target: ctx, selector: #selector(__TimerContext.executeBlock), userInfo: nil, repeats: false)
            }
        #else
            timer = Timer(timeInterval: 0.0, repeats: false, block: {_ in block()})
        #endif
        
        self.add(timer, forMode: RunLoopMode.commonModes)
    }
}
