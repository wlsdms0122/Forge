//
//  SignalWaiter.swift
//  Forge
//
//  Created by JSilver on 8/8/26.
//

import Foundation

final class AsyncSignalWaiter: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false
    private var sources: [DispatchSourceSignal] = []
    
    // MARK: - Initializer
    // MARK: - Public
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            
            installHandlers()
        }
    }
    
    // MARK: - Private
    private func installHandlers() {
        signal(SIGPIPE, SIG_IGN)
        
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler { [weak self] in self?.fire() }
            source.resume()
            
            lock.lock()
            sources.append(source)
            lock.unlock()
        }
    }
    
    private func fire() {
        lock.lock()
        
        guard !fired else {
            lock.unlock()
            
            return
        }
        
        fired = true
        
        let continuation = continuation
        self.continuation = nil
        
        let toCancel = sources
        sources.removeAll()
        
        lock.unlock()
        
        continuation?.resume()
        
        for source in toCancel { source.cancel() }
    }
}
