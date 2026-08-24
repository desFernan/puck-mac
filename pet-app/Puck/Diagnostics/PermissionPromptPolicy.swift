//
//  PermissionPromptPolicy.swift
//  Puck
//
//  owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  When it is acceptable to raise the Accessibility prompt.
//
//  Accessibility is the one permission macOS won't let an app request
//  silently: the only way to ask is a modal that the user must then act on in
//  System Settings. Launch used to raise it whenever the permission was
//  missing, so dismissing it — or being part-way through granting it — earned
//  another dialog on the next launch, forever. Asking is right; asking every
//  time is not. After the first ask the app stays quiet and leaves the door
//  in Settings (PermissionsSection) for whoever wants to grant it later.
//

enum PermissionPromptPolicy {
    static func shouldPromptForAccessibility(isTrusted: Bool, hasAskedBefore: Bool) -> Bool {
        !isTrusted && !hasAskedBefore
    }
}
