import AppKit
import ApplicationServices
import Core
import os

/// Bounded AX hit-test used by automatic mouse selection to avoid treating window chrome
/// as selected content. AX failures and unrecognized trees fail open.
internal struct SelectionGestureTargetProbe: Sendable {
    typealias Lookup = @Sendable (pid_t, CGPoint, Date) -> Bool

    private let lookup: Lookup
    private let timeout: TimeInterval
    private static let queue = DispatchQueue(label: "com.openclip.ax-gesture-target", qos: .userInitiated, attributes: .concurrent)
    private static let inFlight = OSAllocatedUnfairLock(initialState: 0)

    static let `default` = SelectionGestureTargetProbe()

    init(timeout: TimeInterval = Constants.axReadTimeout, lookup: @escaping Lookup = Self.lookupWindowChrome) {
        self.timeout = timeout
        self.lookup = lookup
    }

    /// Returns true only when the point is positively identified as window chrome.
    /// Unknown AX state, including another app's overlay being on top, returns false.
    func isWindowChrome(at point: CGPoint, pid: pid_t) async -> Bool {
        guard pid > 0, !Task.isCancelled else { return false }
        let acquired = Self.inFlight.withLock { count in
            guard count < Constants.axMaxConcurrentInspects else { return false }
            count += 1
            return true
        }
        guard acquired else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        let lookup = self.lookup
        let result = await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Bool) -> Void = { value in
                let won = resumed.withLock { settled in
                    guard !settled else { return false }
                    settled = true
                    return true
                }
                if won { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
            Self.queue.async {
                defer { Self.inFlight.withLock { $0 -= 1 } }
                let chrome = Date() < deadline && lookup(pid, point, deadline)
                finish(Date() < deadline && chrome)
            }
        }
        return !Task.isCancelled && result
    }

    /// Classifies only the hit element and its bounded ancestor chain, ordered from hit
    /// element outward. An editable text role or web area establishes content before a
    /// chrome boundary; this permits controls embedded in toolbars and web content.
    static func isWindowChrome(ancestorRoles: [String], subroles: [String?] = []) -> Bool {
        for (index, role) in ancestorRoles.prefix(8).enumerated() {
            let subrole = index < subroles.count ? subroles[index] : nil
            if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea"].contains(role) {
                return false
            }
            if role == "AXToolbar" || role == "AXTitleBar" || subrole == "AXTitleBar" {
                return true
            }
            // Reaching AXWindow without a toolbar/title bar is ambiguous. Apps with flat or
            // lazily built AX trees (terminals, canvas editors, Electron before its tree exists)
            // report their whole content area as a bare AXWindow hit, so fail open.
            if role == "AXWindow" { return false }
        }
        return false
    }

    private static func lookupWindowChrome(pid: pid_t, point: CGPoint, deadline: Date) -> Bool {
        guard let hit = elementAt(point: point, deadline: deadline) else { return false }
        var hitPID: pid_t = 0
        guard AXUIElementGetPid(hit, &hitPID) == .success, hitPID == pid else { return false }

        var roles: [String] = []
        var subroles: [String?] = []
        var current: AXUIElement? = hit
        while let element = current, roles.count < 8, Date() < deadline {
            guard let role = attribute(kAXRoleAttribute, of: element, deadline: deadline) as? String else { return false }
            roles.append(role)
            subroles.append(attribute(kAXSubroleAttribute, of: element, deadline: deadline) as? String)
            // Editable text is sufficient evidence even if nested in toolbar chrome.
            if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) { return false }
            if role == "AXWebArea" { return false }
            if role == "AXToolbar" || role == "AXTitleBar" || subroles.last == "AXTitleBar" { return true }
            if role == "AXWindow" { return false }
            current = elementAttribute(kAXParentAttribute, of: element, deadline: deadline)
        }
        return isWindowChrome(ancestorRoles: roles, subroles: subroles)
    }

    private static func elementAt(point: CGPoint, deadline: Date) -> AXUIElement? {
        // Never set a messaging timeout on the system-wide element: that changes the global
        // default for every AX element in this process. The caller's deadline race bounds this.
        guard deadline.timeIntervalSinceNow > 0 else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement, deadline: Date) -> AXUIElement? {
        guard let value = attribute(name, of: element, deadline: deadline), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return value as! AXUIElement
    }

    private static func attribute(_ name: String, of element: AXUIElement, deadline: Date) -> CFTypeRef? {
        guard applyTimeout(to: element, deadline: deadline) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func applyTimeout(to element: AXUIElement, deadline: Date) -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        return AXUIElementSetMessagingTimeout(element, Float(remaining)) == .success
    }
}
