// BackgroundCursor.swift
// OpenClip
//
// The window server ignores cursor changes from an app that is not active. Capture Text must stay
// inactive (see CaptureTextController), so it asks the window server to accept them anyway through the
// private `SetsCursorInBackground` connection property, the mechanism screenshot tools rely on.
// The symbols are looked up at runtime: if they disappear, the overlay keeps the arrow cursor.
import CoreFoundation
import Darwin

enum BackgroundCursor {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias SetPropertyFunction = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let functions: (ConnectionFunction, SetPropertyFunction)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connection = dlsym(handle, "_CGSDefaultConnection"),
              let setProperty = dlsym(handle, "CGSSetConnectionProperty") else { return nil }
        return (unsafeBitCast(connection, to: ConnectionFunction.self), unsafeBitCast(setProperty, to: SetPropertyFunction.self))
    }()

    @MainActor
    static func setEnabled(_ enabled: Bool) {
        guard let (connection, setProperty) = functions else { return }
        let id = connection()
        _ = setProperty(id, id, "SetsCursorInBackground" as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }
}
