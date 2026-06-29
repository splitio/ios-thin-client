//  Created by Martin Cardozo
//  Copyright © 2026 Harness. All rights reserved

import Foundation
import Logging

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(WatchKit)
import WatchKit
#endif

typealias AppStateAction = @Sendable () -> Void

enum AppStateChange {
    case didEnterBackground
    case didBecomeActive
}

protocol AppStateManager: Sendable {
    func addObserver(for change: AppStateChange, action: @escaping AppStateAction)
    func removeAllObservers()
}

final class DefaultAppStateManager: AppStateManager, @unchecked Sendable {

    private var actions = [AppStateChange: [AppStateAction]]()
    private let lock = NSLock()
    private var systemObservers = [NSObjectProtocol]()

    #if os(iOS) || os(tvOS)
        private static let didEnterBgNotification = UIApplication.didEnterBackgroundNotification
        private static let didBecomeActiveNotification = UIApplication.didBecomeActiveNotification
    #elseif os(macOS)
        private static let didEnterBgNotification = NSApplication.didResignActiveNotification
        private static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    #elseif os(watchOS)
        private static let didEnterBgNotification = WKExtension.applicationDidEnterBackgroundNotification
        private static let didBecomeActiveNotification = WKExtension.applicationDidBecomeActiveNotification
    #endif

    static let instance = DefaultAppStateManager()

    private init() {
        startObserving()
    }

    deinit {
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func addObserver(for change: AppStateChange, action: @escaping AppStateAction) {
        withLock(lock) {
            actions[change, default: []].append(action)
        }
    }

    func removeAllObservers() {
        withLock(lock) {
            actions.removeAll()
        }
    }

    private func startObserving() {
        let bgObserver = NotificationCenter.default.addObserver(forName: Self.didEnterBgNotification, object: nil, queue: .main) { [weak self] _ in
            self?.executeActions(for: .didEnterBackground)
            Logger.d("Split host app entered background")
        }

        let activeObserver = NotificationCenter.default.addObserver(forName: Self.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.executeActions(for: .didBecomeActive)
            Logger.d("Split host app became active")
        }

        systemObservers = [bgObserver, activeObserver]
    }

    private func executeActions(for change: AppStateChange) {
        let actionsToExecute = withLock(lock) { actions[change] ?? [] }
        for action in actionsToExecute {
            action()
        }
    }
}
