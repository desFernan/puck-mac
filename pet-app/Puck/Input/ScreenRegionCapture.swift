//
//  ScreenRegionCapture.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Interactive drag-to-select screen-region capture for attaching to a
//  message. Shells out to /usr/sbin/screencapture -i rather than
//  reimplementing drag-to-select: it already draws the system's own
//  crosshair overlay, handles Space to switch to window-capture mode, and
//  Escape to cancel -- exactly the interaction this needs, for free.
//
//  Requires the Screen Recording permission (System Settings > Privacy &
//  Security) the same way Accessibility is requested elsewhere -- macOS
//  prompts for it automatically on first use rather than through an
//  Info.plist usage-description key.
//

import Foundation

enum ScreenRegionCapture {
    /// - Parameter completion: the captured file's URL, or nil if the user
    ///   pressed Escape (screencapture still exits 0, it just never writes
    ///   the file) or the process itself couldn't be launched. Always
    ///   called on the main thread.
    static func capture(completion: @escaping (URL?) -> Void) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("Puck-capture-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", path.path]
        process.terminationHandler = { _ in
            let captured = FileManager.default.fileExists(atPath: path.path)
            DispatchQueue.main.async {
                completion(captured ? path : nil)
            }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
