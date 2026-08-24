//
//  IdleState.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  Idle state's StateHandler implementation.
//

import Foundation

/// IdleState does not decide which state to actually transition to when the
/// WanderScheduler timer fires — that decision needs the window list (F4,
/// e.g. finding the nearest window), so it's delegated up to whatever owns
/// CharacterController (the future App bootstrap wiring).
/// `@MainActor`: the implementor is the app delegate and what it decides
/// moves the character, which the frame loop draws on the main thread.
@MainActor
protocol IdleWanderDelegate: AnyObject {
    func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome)

    /// The surface underfoot went behind `window` -- the user brought that
    /// window to the front. Falling is not the answer here (see the call
    /// site), so the decision goes up to whoever knows the settings and the
    /// window list.
    func idleStateDidLoseFootingBehind(_ window: WindowInfo)
}

final class IdleState: StateHandler {
    let name = "Idle"
    let clipKey = "idle"
    let loopsClip = true

    weak var wanderDelegate: IdleWanderDelegate?
    private let scheduler: WanderScheduler

    /// How busy the pet should look, which depends on where it is standing --
    /// see WanderScheduler.Pace. Set by whoever moves it in and out of its
    /// tank.
    var pace: WanderScheduler.Pace {
        get { scheduler.pace }
        set { scheduler.pace = newValue }
    }

    init(scheduler: WanderScheduler = WanderScheduler()) {
        self.scheduler = scheduler
    }

    func update(dt: TimeInterval, context: StateContext) {
        // WalkOnTopState already re-checks its supporting window every frame;
        // Idle never did, so a pet resting after Fall -> Land -> Idle (window
        // tops are valid landing surfaces, see LandingSurfaceResolver) stayed
        // floating in place forever if that window later closed/minimized.
        // landingY(position) > position.y means a gap has opened up below --
        // whatever was there is now gone.
        let surfaceY = context.landingY(context.body.position)
        guard surfaceY <= context.body.position.y + WindowSupport.footTolerance else {
            // Falling is right when the surface is simply gone, and wrong when
            // it only went *behind* something: the pet draws above every
            // window, so dropping to a floor that same window also covers just
            // relocates it from a hidden edge to the middle of the window the
            // user is working in -- which is what clicking the chat window
            // used to do to it (2026-08-22).
            let landing = CGPoint(x: context.body.position.x, y: surfaceY)
            if let covering = WindowSupport.coveringWindow(
                standingAt: landing,
                petHeight: context.avatarHeight,
                in: context.windows
            ) {
                wanderDelegate?.idleStateDidLoseFootingBehind(covering)
            } else {
                context.requestTransition(.fall)
            }
            return
        }

        if let outcome = scheduler.tick(dt: dt) {
            wanderDelegate?.idleStateDidRequestWander(outcome)
        }
    }
}
