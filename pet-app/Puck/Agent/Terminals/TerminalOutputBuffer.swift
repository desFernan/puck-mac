//
//  TerminalOutputBuffer.swift
//  Puck
//
//  What a long-running command has said, and how much of it the agent has
//  already been told.
//
//  `run_shell` runs a command, waits, and hands back everything at once. That
//  is the wrong shape for the thing the agent could not do at all: start a
//  dev server, a test watcher, a build, and then *keep asking what it says*.
//  Those never exit, so "wait for it and return the output" never returns --
//  and `run_shell`'s own answer is capped at 60 seconds, after which the
//  process is killed.
//
//  So output accumulates here instead, and a read takes whatever is new. The
//  cursor is what makes a second read useful: without it every read hands
//  back the whole log again, and a model watching a build would re-read the
//  same ten thousand lines on every turn.
//
//  Bounded, because a dev server left running for a day is unbounded. The
//  oldest goes first -- what a watcher said an hour ago is not what anyone is
//  asking about -- and a read that arrives after a drop is told, because
//  silently handing back a log with a hole in it is worse than saying there
//  is one.
//
//  Pure and separate from the process, because every case worth testing is a
//  boundary: a read with nothing new, a read after a drop, and a buffer that
//  has only ever held one enormous line.
//

import Foundation

struct TerminalOutputBuffer {
    /// How much of one session's output is kept.
    ///
    /// 256KB is a long build log and a short day of a dev server. Past it the
    /// oldest is dropped: a model asking "what does it say now" is asking
    /// about the end.
    static let maximumBytes = 256 * 1024

    /// What a read hands back.
    struct Read: Equatable {
        /// Everything said since the last read.
        let text: String
        /// How many bytes were dropped before this text, or 0. Reported so
        /// the reader can be told there is a hole rather than being handed a
        /// log that silently skips.
        let droppedBytes: Int
        /// Whether anything at all was new.
        var isEmpty: Bool { text.isEmpty && droppedBytes == 0 }
    }

    private var bytes = Data()
    /// How many bytes have ever been appended, which is what the cursor
    /// counts against -- an index into `bytes` would move under the reader
    /// every time the front is dropped.
    private var totalAppended = 0
    /// How much of the total the reader has seen.
    private var readTo = 0
    /// The oldest byte still held, in the same total-based count.
    private var heldFrom = 0

    private let limit: Int

    init(limit: Int = TerminalOutputBuffer.maximumBytes) {
        self.limit = limit
    }

    /// Everything held right now, oldest first. For showing the session, not
    /// for reading it -- this does not move the cursor.
    var all: String { String(decoding: bytes, as: UTF8.self) }

    var isEmpty: Bool { bytes.isEmpty }

    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        bytes.append(data)
        totalAppended += data.count
        guard bytes.count > limit else { return }
        let over = bytes.count - limit
        // Rebuilt rather than `removeFirst(over)`, which does not do what it
        // looks like: `Data` keeps its original index base, so dropping the
        // front leaves `startIndex` at 60 rather than 0 and every offset
        // computed against 0 afterwards is out of range. It crashed the
        // process on the first read after a drop -- not a wrong answer, a
        // trap. Copying the tail normalises the indices and bounds the memory
        // at the same time.
        bytes = Data(bytes.dropFirst(over))
        heldFrom += over
        // The cursor is deliberately left where it is, behind what was just
        // dropped. That gap *is* the record of the loss: `read` reports it as
        // `droppedBytes` and moves up afterwards. Moving the cursor here
        // instead closed the gap before anyone could be told about it, so a
        // reader that had not read at all was handed the surviving tail with
        // no sign that anything came before it.
    }

    /// Everything since the last read, and how much was lost before it.
    ///
    /// - Parameter maximumBytes: the most to hand back in one read. A build
    ///   that produced a megabyte while nobody was looking must not arrive as
    ///   one message -- the far end of this is a model's context.
    mutating func read(maximumBytes: Int = 16 * 1024) -> Read {
        let dropped = max(0, heldFrom - readTo)
        let from = max(readTo, heldFrom)
        guard totalAppended > from else {
            readTo = max(readTo, heldFrom)
            return Read(text: "", droppedBytes: dropped)
        }
        let start = from - heldFrom
        let available = bytes.count - start
        let take = min(available, maximumBytes)
        // A cut lands anywhere, including inside a character.
        // `String(decoding:)` turns the broken half into a replacement rather
        // than losing the line it was in.
        let slice = bytes.subdata(in: bytes.startIndex.advanced(by: start)..<bytes.startIndex.advanced(by: start + take))
        readTo = from + take
        return Read(text: String(decoding: slice, as: UTF8.self), droppedBytes: dropped)
    }

    /// Puts the cursor back to the start of what is held, so the next read
    /// hands back everything again. For a caller that wants the session from
    /// the beginning rather than what is new.
    mutating func rewind() {
        readTo = heldFrom
    }
}
