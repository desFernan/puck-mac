//
//  AppDelegate.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Coordinates the init order: permission self-check -> overlay -> bridge
//  server -> global hotkeys.
//

import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

/// `@MainActor`, stated rather than assumed. Every line of this class and its
/// seventeen extensions runs on the main thread already -- it owns the
/// windows, the menu bar, the frame loop and the character -- but the
/// annotation is what lets the compiler check it, and what stops a callback
/// arriving from a socket queue touching a window by accident.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, IdleWanderDelegate, PetPointingCoordinating {
    let settingsStore = SettingsStore()

    var screenManager: ScreenManager?
    var overlayController: OverlayWindowController?
    var characterController: CharacterController?
    var avatar: SpriteAvatar?
    var sfxPlayer: SFXPlayer?
    var clickThroughController: ClickThroughController?
    /// Backs the menu bar's Hide/Show toggle.
    var isCharacterHidden = false
    var spaceChangeObserver: NSObjectProtocol?
    /// Held for the process's lifetime -- see AppDelegate+Language, which is
    /// the only thing that sets it.
    var languageObserver: NSObjectProtocol?
    var avatarHitboxSize: CGSize = .zero
    /// Unscaled manifest.hitbox -- recomputes avatarHitboxSize when Settings'
    /// size slider live-applies a new scale (applyLiveAvatarScale).
    var baseHitboxSize: CGSize = .zero
    var characterBody: CharacterBody?
    let pendingPointTracker = PendingPointTracker()
    var focusModeObserver: FocusModeObserver?

    /// The one window the pet is drawn in, covering every display (see
    /// OverlayWindowController). Named here rather than repeating
    /// `overlayController?.window` at each of its call sites.
    var overlayWindow: NSWindow? { overlayController?.window }

    /// Every display's work area, in that window's coordinates -- one rect
    /// per display, the Dock and menu bar already taken off. Kept on the
    /// controller as `roamableAreas`; this is where it is measured.
    /// Empty before the overlay exists.
    /// The settings the menu bar panel does not carry -- see
    /// showSettingsWindow(). Kept after closing so it reopens where it was.
    var settingsWindow: NSWindow?

    /// The housings currently painted into the overlay, so a rebuild can
    /// take the old ones down. They belong to the window, and the window is
    /// thrown away and rebuilt on every display change.
    var paintedNotchLayers: [CAShapeLayer] = []

    /// Every camera housing there is, in the pet's own space.
    ///
    /// Measured here, beside `screenWorkAreas`, and for the same reasons: one
    /// entry per display, because a MacBook driving an external monitor has a
    /// housing on exactly one of them and a pet crawling the other screen's
    /// ceiling must not duck around it; and measured when the screens are,
    /// because that is when the answer changes -- a resolution change, a
    /// monitor plugged or unplugged, a fullscreen Space. Reading it per frame
    /// instead meant `NSScreen.screens` thirty times a second for a value
    /// that changes when the hardware does.
    var screenNotches: [ScreenNotch] {
        guard let window = overlayWindow, let space = screenManager?.current else { return [] }
        let origin = space.normalized(fromAppKit: CGPoint(x: window.frame.minX, y: window.frame.maxY))
        return NSScreen.screens.compactMap { screen in
            // The real one where there is one; otherwise this display is
            // given a housing of its own -- see ScreenNotch.virtualAppKitRect
            // for why it is worth giving. A display that has one already gets
            // nothing painted over it, because it is already a piece of black
            // plastic.
            let real = ScreenNotch.appKitRect(
                inScreenFrame: screen.frame,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea
            )
            let appKit = real ?? ScreenNotch.virtualAppKitRect(
                inScreenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
            guard let appKit else { return nil }
            // The same rebasing screenWorkAreas does: into Quartz's top-left
            // space, then onto the overlay window's own origin.
            let topLeft = space.normalized(fromAppKit: CGPoint(x: appKit.minX, y: appKit.maxY))
            return ScreenNotch(
                rect: CGRect(
                    x: topLeft.x - origin.x,
                    y: topLeft.y - origin.y,
                    width: appKit.width,
                    height: appKit.height
                ),
                isVirtual: real == nil
            )
        }
    }

    var screenWorkAreas: [CGRect] {
        guard let window = overlayWindow, let space = screenManager?.current else { return [] }
        let origin = space.normalized(fromAppKit: CGPoint(x: window.frame.minX, y: window.frame.maxY))
        return NSScreen.screens.map { screen in
            // visibleFrame, not frame: it is macOS's own answer to "where may
            // something be put on this display", which is the Dock and the
            // menu bar already subtracted -- per display, which matters the
            // moment the Dock is on one of two monitors, and per Space, which
            // is how a fullscreen Space gives the pet the whole screen back.
            let visible = screen.visibleFrame
            let topLeft = space.normalized(fromAppKit: CGPoint(x: visible.minX, y: visible.maxY))
            return CGRect(
                x: topLeft.x - origin.x,
                y: topLeft.y - origin.y,
                width: visible.width,
                height: visible.height
            )
        }
    }

    /// The window the pet fell behind, until it has landed and been moved onto
    /// that window's top edge -- see perchAfterLandingIfNeeded().
    var pendingPerchWindowID: CGWindowID?
    /// Set when a wander drew the ceiling with no wall underfoot, so the walk
    /// to one knows what it is for -- see climbToCeilingIfArrived().
    var pendingCeilingClimb = false
    /// The one long-lived instance of every state the pet can be in, and the
    /// table that registers them. Twenty-two properties before, each read by
    /// one or two of this file's extensions -- see PetStates.
    let states = PetStates()

    /// Where the pet's tank is and how big the pet is while it is in there.
    /// Four properties and a mutable static before, all touched only by
    /// AppDelegate+Tank -- see TankResidency.
    var tank = TankResidency()
    let petHomeDecider = PetHomeDecider()
    /// The tank the client last reported, in overlay-local coordinates. Nil
    /// The roamable areas the pet had before it went home, so coming out
    /// restores the desktop it actually had rather than a recomputed guess.
    /// Nil is also the answer to "is the pet out on the desktop right now".
    var desktopRoamableAreas: [CGRect]?
    /// The legs of the current wander and the beat between them -- two
    /// properties before, both touched only by AppDelegate+Wander. See
    /// WanderRun.
    var wanderRun = WanderRun()
    var stateBeforePin: StateHandler?
    /// Recognises the cursor being rubbed over the pet's head. Owned here
    /// rather than by ClickThroughController so that type stays about hit
    /// testing, matching how gesture -> FSM mapping already works.
    var headPetDetector = HeadPetDetector()
    /// How far above the pet's head a spun toy floats.
    static let spinHoverGap: CGFloat = 14

    /// A toy in somebody's hand: where it was grabbed and how fast it was
    /// moving when they let go. Three properties before, all of them touched
    /// only by AppDelegate+PetInteraction -- see ToyDrag.
    var toyDrag = ToyDrag()
    /// Every toy that's out, and which one the pet is playing with. The FSM
    /// states above still only ever deal with one toy -- `toyBox.focused`.
    var toyBox: ToyBox?
    /// When the pet last finished playing. Play used to restart the instant
    /// the thrown toy settled, so a toy left out meant the pet did nothing
    /// else ever again -- the pet needs a break between games rather than
    /// playing nonstop.
    var toyPlayEndedAt: TimeInterval?
    /// How long the pet goes without picking a toy up again. Long enough for
    /// a wander or two in between, short enough that a toy put out for it
    /// doesn't feel ignored.
    static let toyPlayCooldown: TimeInterval = 20
    /// Had enough of toys for the moment.
    var isRestingFromToys: Bool {
        guard let toyPlayEndedAt else { return false }
        return CACurrentMediaTime() - toyPlayEndedAt < Self.toyPlayCooldown
    }
    /// The toy the cursor picked up, decided once on mouse-down. Held for the
    /// whole gesture for the same reason ClickThroughController holds its
    /// subject: the toy moves while being dragged, so re-testing per event
    /// could hand the rest of the drag to a different one.
    var grabbedToy: BallController?

    let frameClock = FrameClock()
    var idleFrameRate = IdleFrameRatePolicy()
    // Shared: PointAtHandler starts a pointing session on it, and the frame
    // clock ticks the same instance so the release timeout can elapse.
    let pointingController = PointingController()

    var windowListWatcher: WindowListWatcher?
    var toolExecutor: ToolExecutor?

    var bridgeServer: BridgeServer?
    var bridgeMessageRouter: BridgeMessageRouter?

    var hotkeyManager: GlobalHotkeyManager?
    /// Runs only while the hotkeys are waiting for Accessibility to be
    /// granted; cleared by the retry itself once the tap is live.
    var accessibilityRetryTimer: Timer?
    /// The tank's size as the client last reported it, kept so the pet can be
    /// The scale the trip in progress is heading for. Held here rather than
    var voiceInputController: VoiceInputController?
    var stateBeforeListen: StateHandler?

    var menuBarController: MenuBarController?
    var textInputBubbleWindow: TextInputBubbleWindow?

    // The following three properties are declared here rather than in the
    // extension file that uses them, because Swift extensions cannot add
    // stored instance properties to a class -- only computed properties and
    // methods. Each is otherwise "owned" by one extension's logic.
    /// Flushed by BridgeServer.onGUIPresenceChanged; only ever the most
    /// recent submission, since an older one being delivered late alongside
    /// it would be noise, not history.
    var pendingClientMirror: BridgeMessage?
    /// True from the moment guidance starts until its bubble expires.
    var isGuidingPermission = false
    /// Which timed notice the shared bubble window is currently showing --
    /// see showNoticeBubble(). Bumped per notice so an earlier one's expiry
    /// timer cannot close the notice that replaced it.
    var noticeBubbleGeneration = 0
    /// Which generation the live-caption bubble took, or nil when the hold is
    /// not showing one. Releasing the key closes the bubble only while this
    /// still matches -- by then a notice may have replaced the captions, and
    /// that notice's own timer owns the window.
    var captionBubbleGeneration: Int?
    /// Set once a capture completes, cleared on submit/cancel/dismiss --
    /// see AppDelegate+HotkeysVoice.swift's showTextInputBubble(). At most
    /// one: the panel has room for a single thumbnail, and multi-image
    /// messages aren't something the quick-capture bubble needs to support.
    var pendingBubbleAttachment: Attachment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only ever one pet: a second launch (double-click, or a Debug build
        // next to an installed copy -- same bundle id either way) quits
        // itself instead of stacking a second character and menu bar item.
        // Not under XCTest -- the test runner hosts this same app, and the
        // guard tripping on an already-running pet kills the whole test run.
        let processInfo = ProcessInfo.processInfo
        let isHostingTests = processInfo.environment["XCTestSessionIdentifier"] != nil
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? AppIdentity.puckBundleID)
        if !isHostingTests, peers.contains(where: { $0.processIdentifier != processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        // Before anything that builds UI text: the menu bar, Settings and the
        // pet's own bubbles all read `Strings` at construction.
        setUpLanguage()
        requestPermissions()
        setUpAppearance()
        setUpClientThemeStyle()

        // The two processes have to come up together -- PuckClient (the F13
        // client window, now a separate Dock-resident app) is useless without
        // this process hosting bridge.sock, so each launches the other.
        setUpMenuBar()
        setUpOverlayAndAvatar()
        setUpWindowSensing()
        setUpToolExecutor()
        setUpBridgeServer()
        // After the socket exists, not before (2026-08-15). Launched first,
        // PuckClient reliably lost the race and its NWConnection parked in
        // `.waiting` on a path with no listener. BridgeConnection now treats
        // that as a close and retries, so this ordering is no longer load-
        // bearing -- but starting the client into a socket that is already
        // there beats starting it into one that isn't and recovering.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: AppIdentity.puckClientBundleID)
        setUpGlobalHotkeys()
        setUpFrameLoop()
        setUpSpaceChangeObserving()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Everything started in applicationDidFinishLaunching gets torn down
        // here. BridgeServer is the one that matters beyond this process:
        // stop() unlinks the socket and drops the advisory lock, and skipping
        // it leaves a dead endpoint in Application Support that a client can
        // still connect to. The lock itself the kernel releases either way.
        frameClock.stop()
        hotkeyManager?.stop()
        voiceInputController?.pushToTalkUp()
        bridgeServer?.stop()
        windowListWatcher?.stop()
        focusModeObserver?.stopObserving()
        clickThroughController?.stopMonitoring()
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
    }
}
