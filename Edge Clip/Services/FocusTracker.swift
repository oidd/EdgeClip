import AppKit
import Foundation

@MainActor
final class FocusTracker {
    private let ownBundleID = Bundle.main.bundleIdentifier
    private(set) var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
        let ownBundleID = ownBundleID
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self, ownBundleID] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier != ownBundleID
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.lastExternalApp = app
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    func captureCurrentFrontmostApp() {
        guard
            let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != ownBundleID
        else {
            return
        }

        lastExternalApp = app
    }

    @discardableResult
    func restoreLastExternalApp() -> Bool {
        guard let app = lastExternalApp else { return false }
        return app.activate(options: [])
    }
}
