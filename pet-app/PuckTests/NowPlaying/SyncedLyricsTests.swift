//
//  SyncedLyricsTests.swift
//  PuckTests
//
//  Reading an LRC file, and knowing which line is being sung.
//

import XCTest
@testable import Puck

final class SyncedLyricsTests: XCTestCase {
    private let sample = """
    [ar:비오]
    [ti:리무진]
    [00:12.00]첫 번째 줄
    [00:15.50]두 번째 줄
    [01:02.25]세 번째 줄
    """

    func test_itReadsTheTimestampsAndTheWords() {
        let lyrics = SyncedLyrics.parse(sample)

        XCTAssertEqual(lyrics.lines.count, 3, "the metadata tags are not lyrics")
        XCTAssertEqual(lyrics.lines[0].time, 12)
        XCTAssertEqual(lyrics.lines[1].time, 15.5)
        XCTAssertEqual(lyrics.lines[2].time, 62.25, "a minute and two seconds")
        XCTAssertEqual(lyrics.lines[0].text, "첫 번째 줄")
    }

    /// A title card appearing mid-song reads as the wrong lyric.
    func test_metadataIsNotShownAsALyric() {
        let lyrics = SyncedLyrics.parse(sample)

        XCTAssertFalse(lyrics.lines.contains { $0.text.contains("비오") })
        XCTAssertFalse(lyrics.lines.contains { $0.text.contains("리무진") })
    }

    /// A line stays up until the next one starts. Picking the *nearest*
    /// instead flicks to the next line halfway through the current one.
    func test_aLineStaysUpUntilTheNextOne() {
        let lyrics = SyncedLyrics.parse(sample)

        XCTAssertEqual(lyrics.line(at: 12)?.text, "첫 번째 줄")
        XCTAssertEqual(lyrics.line(at: 15.4)?.text, "첫 번째 줄", "still the first, though the second is closer")
        XCTAssertEqual(lyrics.line(at: 15.5)?.text, "두 번째 줄")
        XCTAssertEqual(lyrics.line(at: 999)?.text, "세 번째 줄", "the last one holds to the end")
    }

    /// Before the first line there is nothing to show -- an intro is not the
    /// first verse arriving early.
    func test_beforeTheFirstLineThereIsNothing() {
        XCTAssertNil(SyncedLyrics.parse(sample).line(at: 0))
        XCTAssertNil(SyncedLyrics.parse(sample).line(at: 11.9))
    }

    /// A chorus sung four times is written once with four timestamps.
    func test_oneLineCanCarrySeveralTimestamps() {
        let lyrics = SyncedLyrics.parse("[00:10.00][01:10.00][02:10.00]후렴")

        XCTAssertEqual(lyrics.lines.count, 3)
        XCTAssertEqual(lyrics.line(at: 70)?.text, "후렴")
        XCTAssertEqual(lyrics.line(at: 130)?.text, "후렴")
    }

    /// And they arrive out of order by construction, so the order is made
    /// here rather than trusted.
    func test_theLinesComeBackInTimeOrder() {
        let lyrics = SyncedLyrics.parse("[00:30.00]나중\n[00:10.00]먼저")

        XCTAssertEqual(lyrics.lines.map(\.text), ["먼저", "나중"])
        XCTAssertEqual(lyrics.line(at: 20)?.text, "먼저")
    }

    /// `mm:ss` with no fraction is legal, and some sources use a comma.
    func test_theOtherTimestampShapes() {
        XCTAssertEqual(SyncedLyrics.parse("[01:05]가사").lines.first?.time, 65)
        XCTAssertEqual(SyncedLyrics.parse("[01:05,50]가사").lines.first?.time, 65.5)
    }

    /// A song with no lyrics is the ordinary case, not an error.
    func test_nothingAtAll() {
        XCTAssertTrue(SyncedLyrics.parse("").isEmpty)
        XCTAssertNil(SyncedLyrics.parse("").line(at: 10))
        XCTAssertTrue(SyncedLyrics.parse("just some words\nwith no times").isEmpty)
    }
}
