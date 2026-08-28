//
//  BrowserTitleTests.swift
//  PuckTests
//
//  A tab title is not a song name until the tab bar's own additions are
//  taken back off it.
//

import XCTest
@testable import Puck

final class BrowserTitleTests: XCTestCase {
    /// The shape almost every music page uses.
    func testArtistAndTitleAreSplitOnTheDash() {
        let parsed = BrowserTitle.parse("Radiohead - Creep - YouTube")

        XCTAssertEqual(parsed?.artist, "Radiohead")
        XCTAssertEqual(parsed?.title, "Creep")
    }

    /// A title with its own dashes must not be cut at the last one: the
    /// artist is the part in front, so only the first dash counts.
    func testOnlyTheFirstDashSplits() {
        let parsed = BrowserTitle.parse("Joji - SLOW DANCING IN THE DARK - Official Video - YouTube")

        XCTAssertEqual(parsed?.artist, "Joji")
        XCTAssertEqual(parsed?.title, "SLOW DANCING IN THE DARK - Official Video")
    }

    /// The count a tab bar puts in front of a title that has notifications.
    func testTheUnreadCountIsStripped() {
        let parsed = BrowserTitle.parse("(3) Some Song - YouTube")

        XCTAssertEqual(parsed?.title, "Some Song")
    }

    /// Brackets that are part of the name are not a count.
    func testBracketsThatAreNotACountAreKept() {
        let parsed = BrowserTitle.parse("(Don't Fear) The Reaper")

        XCTAssertEqual(parsed?.title, "(Don't Fear) The Reaper")
    }

    /// Longest suffix first, or "- YouTube Music" is left as " Music".
    func testTheLongerSiteNameWins() {
        let parsed = BrowserTitle.parse("Some Song - YouTube Music")

        XCTAssertEqual(parsed?.title, "Some Song")
        XCTAssertEqual(parsed?.artist, "")
    }

    /// A page with no dash is just a title.
    func testNoDashMeansNoArtist() {
        let parsed = BrowserTitle.parse("Lo-fi beats to study to - SoundCloud")

        XCTAssertEqual(parsed?.title, "Lo-fi beats to study to")
        XCTAssertEqual(parsed?.artist, "")
    }

    /// An empty tab, or a browser that answered with nothing, must not put a
    /// blank line in the panel.
    func testNothingWorthShowingIsNothing() {
        XCTAssertNil(BrowserTitle.parse(""))
        XCTAssertNil(BrowserTitle.parse("   "))
        XCTAssertNil(BrowserTitle.parse("- YouTube"))
    }

    /// A renderer helper counts as its browser: which of the two CoreAudio
    /// reports varies, and matching only the parent misses the sound.
    func testAHelperProcessCountsAsItsBrowser() {
        let browser = Browser.makingSound(
            among: ["com.google.Chrome.helper.Renderer"],
            running: ["com.google.Chrome"]
        )

        XCTAssertEqual(browser?.applicationName, "Google Chrome")
    }

    /// Something that merely shares a word is not a browser.
    func testAnUnrelatedAppIsNotABrowser() {
        XCTAssertNil(Browser.makingSound(
            among: ["com.apple.Music", "com.hnc.DiscordPTB"],
            running: ["com.apple.Music", "com.google.Chrome"]
        ))
    }

    /// Dia's renderer answers to `company.thebrowser.browser.helper`, which
    /// is also what Arc's would be. Picking by that alone named whichever
    /// was listed first and then asked an app that is not open what it is
    /// playing, so nothing ever appeared.
    func testTwoBrowsersSharingAHelperAreToldApartByWhichIsRunning() {
        let helper: Set<String> = ["company.thebrowser.browser.helper"]

        XCTAssertEqual(
            Browser.makingSound(among: helper, running: ["company.thebrowser.dia"])?.applicationName,
            "Dia"
        )
        XCTAssertEqual(
            Browser.makingSound(among: helper, running: ["company.thebrowser.Browser"])?.applicationName,
            "Arc"
        )
    }

    /// A browser that is not open cannot be the one making the sound, and
    /// asking it would only fail.
    func testABrowserThatIsNotRunningIsNeverPicked() {
        XCTAssertNil(Browser.makingSound(
            among: ["com.google.Chrome.helper.Renderer"],
            running: ["com.apple.Music"]
        ))
    }
}
