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

    /// OverlayWindowController creates one window per display, but every
    /// ground/roamable/click-through computation in this file is scoped to
    /// a single display -- multi-monitor support is not implemented, this
    /// just names the existing single-display assumption in one place
    /// instead of repeating `overlayController?.windows.first` at each site.
    var primaryWindow: NSWindow? { overlayController?.windows.first }

    // One shared instance per FSM state, reused for every transition into it.
    // CharacterController.transition's same-state no-op guard is reference
    // equality (StateHandler: AnyObject) -- constructing a fresh instance per
    // transition (e.g. `IdleState()` each time) defeated that guard, silently
    // resetting IdleState's WanderScheduler timer and replaying loop clip/SFX
    // on every repeated same-kind event.
    let idleState = IdleState()
    let walkState = WalkState()
    let climbState = ClimbState()
    let walkOnTopState = WalkOnTopState()
    let fallState = FallState()
    let landState = LandState()
    let moveToState = MoveToState()
    let travelState = TravelState()
    /// The window the pet fell behind, until it has landed and been moved onto
    /// that window's top edge -- see perchAfterLandingIfNeeded().
    var pendingPerchWindowID: CGWindowID?
    let petHomeDecider = PetHomeDecider()
    /// The tank the client last reported, in overlay-local coordinates. Nil
    /// when there is none to go to.
    var petTankArea: CGRect?
    /// The roamable area the pet had before it went home, so coming out
    /// restores the desktop it actually had rather than a recomputed guess.
    var desktopRoamableArea: CGRect?
    /// The avatar scale the pet had before it went home. There is no stored
    /// setting to read it back from -- the size slider passes a scale straight
    /// to applyLiveAvatarScale and nothing keeps it -- so it is remembered
    /// here for the trip back out.
    var desktopAvatarScale: Double = 1
    /// Legs of the current wander still to walk, and the pause before the next
    /// one -- see continueWanderIfNeeded(dt:).
    var pendingWanderLegs = 0
    var wanderLegPause: TimeInterval = 0
    let typeState = TypeState()
    let pointState = PointState()
    let listenState = ListenState()
    let reactClickState = ReactClickState()
    let reactDragState = ReactDragState()
    // Double-tap "petting" interaction (2026-07-29, more interactions).
    let pettingState = PettingState()
    let spinState = SpinState()
    // F13 (2026-07-29): Option+Shift+Space pins the character while the
    // client window is open, same "capture then restore" pattern as
    // stateBeforeListen below.
    let pinnedState = PinnedState()
    var stateBeforePin: StateHandler?
    /// Recognises the cursor being rubbed over the pet's head. Owned here
    /// rather than by ClickThroughController so that type stays about hit
    /// testing, matching how gesture -> FSM mapping already works.
    var headPetDetector = HeadPetDetector()
    /// Where the toy sat relative to the cursor when it was picked up.
    var toyGrabOffset: CGPoint = .zero
    /// How far above the pet's head a spun toy floats.
    static let spinHoverGap: CGFloat = 14

    /// The toy's throw speed, measured the same way the pet's is.
    var toyThrowVelocity = CursorVelocityTracker()
    /// Mouse events don't arrive on a clock, so the tracker's dt comes from
    /// the gap between them.
    var lastToyDragTime: TimeInterval?
    // F3 ceiling-crawling (2026-07-29): WanderScheduler's .climbToCeiling outcome.
    let climbToCeilingState = ClimbToCeilingState()
    let ceilingState = CeilingState()
    // F12 (optional, lowest priority): ball-toy interaction.
    let chaseBallState = ChaseBallState()
    let juggleBallState = JuggleBallState()
    let kickBallState = KickBallState()
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
    /// sized to fit it rather than being refused by it.
    var lastTankSize: CGSize?
    /// The scale the trip in progress is heading for. Held here rather than
    /// captured by the trip's closure so the size lever can change it
    /// mid-flight.
    var travelTargetScale: Double = 1
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
