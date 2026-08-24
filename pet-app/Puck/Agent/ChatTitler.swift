//
//  ChatTitler.swift
//  Puck
//
//  Names a chat after what it turned out to be about, from its first exchange.
//
//  A separate one-shot call rather than a tool offered to the agent: a tool
//  would ride on every turn's spec whether or not a name was wanted, and would
//  only fire when the model chose to call it -- which is exactly the kind of
//  thing it skips once a task gets interesting. One small call, once per chat,
//  fires every time.
//
//  Deliberately *after* ChatSession's own first-message naming rather than
//  instead of it: that one is instant and free and works with no API key at
//  all, so it stays as the name the user sees immediately and as the fallback
//  when this call fails. This only ever replaces a name that was already there.
//

import Foundation

struct ChatTitler {
    let client: any AgentLLMClient

    /// Asks for a title and returns nil rather than throwing: a chat that
    /// could not be renamed keeps the name it already has, which is a fine
    /// outcome and not worth propagating as an error.
    func title(user: String, reply: String) async -> String? {
        // Both halves are truncated: a title needs the shape of the exchange,
        // not all of it, and an unbounded paste would otherwise set the cost
        // of naming a chat to the cost of the chat.
        let prompt = """
        아래는 어떤 대화의 첫 주고받음이야. 이 대화를 목록에서 알아볼 수 있는 짧은 제목을 지어줘.

        규칙:
        - 한 줄, 공백 포함 20자 이내
        - 명사구로. 문장이나 인사말 금지
        - 따옴표, 마침표, 접두사("제목:" 같은) 금지
        - 대화가 쓰인 언어를 그대로 사용

        사용자: \(Self.clip(user))
        답변: \(Self.clip(reply))
        """

        do {
            let turn = try await client.send(messages: [.user(prompt)], tools: [])
            return Self.sanitised(turn.text)
        } catch {
            return nil
        }
    }

    /// Enough of one side to tell what the exchange is about.
    private static func clip(_ text: String) -> String {
        let limit = 500
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    /// Models answer this kind of ask with the title alone most of the time,
    /// and with `제목: "고양이 산책"` the rest of the time. Both have to come
    /// out the same, because a sidebar row is not the place to discover the
    /// model was chatty.
    private static let titleLabels: Set<String> = ["제목", "title"]

    static func sanitised(_ text: String?) -> String? {
        guard let text else { return nil }
        var line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        // Only a label this app recognises is dropped. Judging by how early
        // the colon appears instead cut "빌드 실패: 링커 오류" down to its second
        // half -- a colon is punctuation a real title is allowed to contain.
        if let colon = line.firstIndex(of: ":") {
            let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if Self.titleLabels.contains(label) {
                line = String(line[line.index(after: colon)...])
            }
        }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’「」`*.·"))
        return line.isEmpty ? nil : line
    }
}
