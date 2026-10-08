import AppKit
import SwiftUI
import Darwin
import Security

@MainActor
final class WalletLifecycle {
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static let closedWindows = NSHashTable<NSWindow>.weakObjects()
    private static var systemSuspended = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let onLastWalletClose: () -> Void
    private let onLock: () -> Void
    private let onInterfaceLock: () -> Void
    private let nativeAuthenticationPending: () -> Bool

    static var sessionEligible: Bool {
        !systemSuspended && windows.allObjects.contains {
            !closedWindows.contains($0) && ($0.isVisible || $0.isMiniaturized || NSApplication.shared.isHidden)
        }
    }

    static var unlockEligible: Bool {
        sessionEligible && NSApplication.shared.isActive && !NSApplication.shared.isHidden &&
        NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() &&
        windows.allObjects.contains { $0.isVisible && !$0.isMiniaturized }
    }

    static func register(_ window: NSWindow) {
        if !closedWindows.contains(window) { windows.add(window) }
    }

    init(onLock: @escaping () -> Void, onLastWalletClose: @escaping () -> Void, onInterfaceLock: @escaping () -> Void, nativeAuthenticationPending: @escaping () -> Bool) {
        self.onLastWalletClose = onLastWalletClose
        self.onLock = onLock
        self.onInterfaceLock = onInterfaceLock
        self.nativeAuthenticationPending = nativeAuthenticationPending
        let appCenter = NotificationCenter.default
        observe(appCenter, NSApplication.willResignActiveNotification) { [weak self] _ in
            guard let self else { return }
            if self.nativeAuthenticationPending() {
                DispatchQueue.main.async { self.checkAuthenticationForeground() }
            } else { self.onInterfaceLock() }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, self.nativeAuthenticationPending() else { return }
            guard let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                self.onInterfaceLock(); return
            }
            if activated.processIdentifier == getpid() { return }
            guard Self.isApprovedNativeAuthentication(activated) else { self.onInterfaceLock(); return }
            self.checkAuthenticationForeground()
        }
        observe(appCenter, NSApplication.didHideNotification) { [weak self] _ in self?.onInterfaceLock() }
        observe(appCenter, NSWindow.willCloseNotification) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.windows.contains(window) else { return }
            Self.closedWindows.add(window)
            Self.windows.remove(window)
            if !Self.sessionEligible { self?.onLastWalletClose() }
        }
        observe(appCenter, NSWindow.didBecomeKeyNotification) { note in
            guard let window = note.object as? NSWindow, Self.closedWindows.contains(window) else { return }
            Self.closedWindows.remove(window)
            Self.windows.add(window)
        }
        observe(appCenter, NSWindow.willMiniaturizeNotification) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.windows.contains(window) else { return }
            if !Self.windows.allObjects.contains(where: { $0 !== window && $0.isVisible && !$0.isMiniaturized }) {
                self?.onInterfaceLock()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspaceCenter, name) { [weak self] _ in
                Self.systemSuspended = true
                self?.onLock()
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspaceCenter, name) { _ in Self.systemSuspended = false }
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] _ in
            Self.systemSuspended = true
            self?.onLock()
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { _ in
            Self.systemSuspended = false
        }
    }

    static var nativeAuthenticationIsForeground: Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        return isApprovedNativeAuthentication(application)
    }

    private static func isApprovedNativeAuthentication(_ application: NSRunningApplication) -> Bool {
        guard ["com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent"].contains(application.bundleIdentifier ?? "") else {
            return false
        }
        let attributes = [kSecGuestAttributePid as String: application.processIdentifier] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let expression = "anchor apple and (identifier \"com.apple.SecurityAgent\" or identifier \"com.apple.LocalAuthentication.UIAgent\")"
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func checkAuthenticationForeground() {
        guard nativeAuthenticationPending() else { return }
        if Self.unlockEligible || Self.nativeAuthenticationIsForeground { return }
        onInterfaceLock()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (Notification) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { action(note) }
        }
        observers.append((center, observer))
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}

struct WalletWindowTracking: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WalletLifecycle.register(window) }
        }
    }
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ view: WindowView, context: Context) {
        if let window = view.window { WalletLifecycle.register(window) }
    }
}
