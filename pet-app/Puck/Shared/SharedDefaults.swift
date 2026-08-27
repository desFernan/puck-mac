//
//  SharedDefaults.swift
//  Puck
//
//  The defaults domain both apps read a shared setting from.
//
//  Puck's, whichever process is asking: one setting with two stores is two
//  settings that disagree, and the pet and the chat window disagreeing about
//  the language or the theme is visible in the same glance.
//
//  Here rather than as a static on whichever type happened to need it first.
//  It was ClientThemeStyle's, so the string table's own appearance setting
//  reached into the client window's layer to find out where a UserDefaults
//  suite lives.
//

import Foundation

enum SharedDefaults {
    static var puck: UserDefaults? {
        UserDefaults(suiteName: AppIdentity.puckBundleID)
    }
}
