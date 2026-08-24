//
//  AppDelegate+WindowSensing.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Starts the window-list watcher (level 1 of window sensing).
//

extension AppDelegate {
    // MARK: - Window sensing (F4 level 1)

    func setUpWindowSensing() {
        let watcher = WindowListWatcher()
        watcher.start()
        windowListWatcher = watcher
    }
}
