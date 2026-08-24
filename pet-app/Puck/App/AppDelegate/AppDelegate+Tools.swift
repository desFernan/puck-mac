//
//  AppDelegate+Tools.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Registers the tool handlers the bridge server dispatches into.
//

import Foundation

extension AppDelegate {
    // MARK: - Tools (F11)

    func setUpToolExecutor() {
        guard let windowListWatcher else { return }

        let executor = ToolExecutor(logger: ToolExecutionLogger())
        executor.onPermissionDenied = { [weak self] tool in self?.guideThroughPermission(deniedFor: tool) }
        let launchApp = LaunchAppHandler()
        launchApp.onLaunchRequested = { [weak self] in self?.performSummonGesture() }
        launchApp.onAppLaunched = { [weak self] pid in self?.sendPetToWindow(ownedBy: pid) }
        executor.register(launchApp)
        executor.register(ListRunningAppsHandler())
        executor.register(GetFrontmostWindowHandler(watcher: windowListWatcher))
        executor.register(RunShellHandler())
        executor.register(RunAppleScriptHandler())
        executor.register(PointAtHandler(coordinator: self))
        executor.register(ClickElementHandler())
        executor.register(FindUIElementHandler())
        toolExecutor = executor
    }
}
