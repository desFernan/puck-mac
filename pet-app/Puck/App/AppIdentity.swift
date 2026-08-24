//
//  AppIdentity.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  The one file to edit when the app gets renamed again -- future renames
//  should be quick, not another manual sweep. The PetAgent -> Shaydi
//  rename touched ~340 files by hand because nothing was centralized --
//  every bundle-id string and Application Support path was a separate
//  literal scattered across both targets.
//
//  This does NOT fully eliminate a rename's cost -- Xcode target names,
//  the on-disk directory names, and project.yml's own target/path/bundle-id
//  entries still have to change, since those are structural, not values a
//  Swift constant can parameterize. What it does do: every *cross-process*
//  string literal (the two bundle IDs each app needs to find the other,
//  and the Application Support directory name both share for bridge.sock)
//  now lives in exactly one place instead of N -- see scripts/rename-app.sh
//  for the rest of the procedure.
//
//  Keep these two bundle IDs in sync with project.yml's
//  PRODUCT_BUNDLE_IDENTIFIER for the Puck/PuckClient targets --
//  xcodegen doesn't read Swift source, so this file and project.yml both
//  have to be updated by hand (or by the rename script) on a rename.
//

enum AppIdentity {
    /// Must match project.yml's Puck target PRODUCT_BUNDLE_IDENTIFIER.
    static let puckBundleID = "com.speaki-e.Puck"
    /// Must match project.yml's PuckClient target PRODUCT_BUNDLE_IDENTIFIER.
    static let puckClientBundleID = "com.speaki-e.PuckClient"

    /// The subdirectory under ~/Library/Application Support/ where
    /// bridge.sock, its lock file, and logs live. Shared by both apps --
    /// if this ever drifts out of sync between them, they can no longer
    /// find each other's socket.
    static let applicationSupportDirectoryName = "Puck"

    /// User-facing name for the pet app.
    static let displayName = "Puck"
    /// User-facing name for the chat/agent client app.
    static let clientDisplayName = "PuckClient"
}
