//
//  ClickDetector.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Global click monitor, checks whether the click point is within a target's frame
//

import AppKit
import CoreGraphics

/// What PointingController needs from click detection — kept as a protocol
/// so it's testable without a real global event monitor.
protocol ClickDetectorProviding: AnyObject {
    var onClickInsideTarget: (() -> Void)? { get set }
    func startMonitoring(targetFrame: CGRect)
    func stopMonitoring()
}

final class ClickDetector: ClickDetectorProviding {
    var onClickInsideTarget: (() -> Void)?

    private var monitor: Any?
    private var targetFrame: CGRect = .zero
    private let mouseLocationProvider: () -> CGPoint
    private let screenSpaceProvider: () -> GlobalScreenSpace?

    /// `targetFrame` (point_at/UIElementInspector) arrives in global Quartz
    /// coordinates (top-left origin, Y-down) -- protocol section 4 -- but
    /// NSEvent.mouseLocation is AppKit's global space (bottom-left origin,
    /// Y-up). Comparing them directly silently misses genuine clicks on the
    /// target (found via review); mouseLocationProvider/screenSpaceProvider
    /// exist so a test can inject both sides of that conversion.
    init(
        mouseLocationProvider: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        screenSpaceProvider: @escaping () -> GlobalScreenSpace? = { GlobalScreenSpace.current() }
    ) {
        self.mouseLocationProvider = mouseLocationProvider
        self.screenSpaceProvider = screenSpaceProvider
    }

    /// Calling this again without an intervening stopMonitoring() (e.g.
    /// re-pointing at a new target before the previous point released)
    /// previously leaked the earlier global monitor.
    func startMonitoring(targetFrame: CGRect) {
        stopMonitoring()
        self.targetFrame = targetFrame
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleClick()
        }
    }

    /// Same reason as WindowListWatcher's: AppKit holds the global monitor,
    /// so dropping the detector without stopping it leaves the monitor
    /// running for the life of the process.
    deinit {
        stopMonitoring()
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    func handleClick() {
        // If the display configuration can't be determined right now, there's
        // no safe way to convert the click -- skip it rather than compare
        // raw AppKit coordinates against a Quartz-space frame.
        guard let normalized = screenSpaceProvider()?.normalized(fromAppKit: mouseLocationProvider()) else { return }
        if Self.isClick(at: normalized, insideTargetFrame: targetFrame) {
            onClickInsideTarget?()
        }
    }

    /// Pure hit test — both values must already be in the same coordinate space.
    static func isClick(at location: CGPoint, insideTargetFrame frame: CGRect) -> Bool {
        frame.contains(location)
    }
}
