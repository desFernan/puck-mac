//
//  AgentRunner+Failures.swift
//  Puck
//
//  What a failed run says, in the transcript and in the log.
//
//  Split out of AgentRunner.swift because none of it touches a run: every
//  member here is static, takes the error and returns text. Keeping it beside
//  the loop meant reading eighty lines of provider-response handling to get
//  from one half of the loop to the other.
//

import Foundation

extension AgentRunner {
    /// The one line a failed run leaves in the transcript.
    ///
    /// `GPTError.errorDescription` inlines the provider's response body on
    /// purpose -- it is the debugging text, and it is what goes to the log --
    /// but a bad key made that ~20 lines of OpenAI's JSON in the chat for what
    /// is really "your key is wrong". This maps the statuses that mean
    /// something the user can act on to a sentence saying what to do, and
    /// leaves every other kind of failure its own words rather than collapsing
    /// the lot into one generic apology.
    ///
    /// Provider-neutral, like `GPTError` itself: the same path serves
    /// Anthropic, and whoever reads this already knows which provider is
    /// selected.
    static func failureSummary(for error: Error) -> String {
        switch error {
        case GPTError.notConfigured:
            return String(format: Strings.text(.agentNoAPIKeyFormat), settingsHint)
        case GPTError.http(let status, let body):
            return httpFailureSummary(status: status, body: body)
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Everything the error knew, for the log.
    static func rawFailureDescription(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// ⌘, opens Settings in both apps (ClientMainMenu binds it), so naming the
    /// shortcut is a real instruction and not decoration.
    private static var settingsHint: String { Strings.text(.agentSettingsHint) }

    private static func httpFailureSummary(status: Int, body: String) -> String {
        switch status {
        case 401, 403:
            return String(format: Strings.text(.agentBadAPIKeyFormat), settingsHint)
        case 404:
            // What a wrong model name returns; a missing endpoint would be our
            // bug, and then the log is where to look anyway.
            return Strings.text(.agentModelNotFound)
        case 429:
            return Strings.text(.agentRateLimited)
        case 500...599:
            return String(format: Strings.text(.agentServerErrorFormat), "\(status)")
        default:
            // Anything else keeps the provider's own reason -- a bare status
            // does not say what to change -- but one sentence of it, not the
            // envelope it arrived in.
            guard let message = providerMessage(in: body) else {
                return String(format: Strings.text(.agentAPIErrorFormat), "\(status)")
            }
            return String(format: Strings.text(.agentAPIErrorWithMessageFormat), "\(status)", message)
        }
    }

    /// `{"error": {"message": ...}}` -- the shape both providers use. Returns
    /// nil for a body that isn't that, rather than guessing: a truncated slice
    /// of unknown JSON is the noise this exists to remove.
    private static func providerMessage(in body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        let firstLine = message
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return nil }
        // A DoneRow is one caption line; a provider that answers with a
        // paragraph gets the head of it, and the log keeps the rest.
        return firstLine.count <= 160 ? firstLine : String(firstLine.prefix(160)) + "…"
    }
}
