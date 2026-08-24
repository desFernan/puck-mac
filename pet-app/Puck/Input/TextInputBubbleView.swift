//
//  TextInputBubbleView.swift
//  Puck
//
//  owner: 박해영 (Haeyoung Park)
//  NSVisualEffectView + NSTextField bubble UI
//
//  Enter -> onSubmit (protocol 3.3 user_input(source: "text")); Escape ->
//  onCancel. If the socket isn't connected, the caller is responsible for
//  showing a "워크스페이스 꺼져있음" bubble instead of actually sending —
//  that's Bridge-layer knowledge this view doesn't have.

import AppKit

final class TextInputBubbleView: NSView {
    private let textField = NSTextField()
    private let attachButton = NSButton()
    private let thumbnailView = NSImageView()
    private var isShowingMessage = false
    /// Toggled between the two, depending on whether a thumbnail is showing
    /// -- see configureAttachmentViews().
    ///
    /// `lazy` rather than implicitly unwrapped: both are built from views
    /// this class owns outright, so there is no window in which they are
    /// legitimately nil, and an unwrapped optional only offers a crash if the
    /// setup order is ever changed. Made on first use, which is activation --
    /// after both views have been added, which is what activation requires.
    private lazy var textFieldLeadingWithoutThumbnail = textField.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Self.horizontalInset
    )
    private lazy var textFieldLeadingWithThumbnail = textField.leadingAnchor.constraint(
        equalTo: thumbnailView.trailingAnchor, constant: Self.horizontalInset / 2
    )

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    /// F14 (2026-08-01): the attach button was clicked -- the caller owns
    /// actually running the capture (ScreenRegionCapture) and protocol
    /// Attachment types; this view only ever shows/hides a thumbnail image.
    var onAttachRequested: (() -> Void)?
    /// The thumbnail itself is the remove control -- clicking it drops the
    /// pending attachment, no separate close button needed.
    var onRemoveAttachment: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installBackground()
        configureTextField()
        configureAttachmentViews()
    }

    /// Real Liquid Glass on macOS 26, the Spotlight-style vibrant slab it
    /// always had before that. The background is a sibling *below* the text
    /// field, not its superview -- the field stays a direct subview so
    /// first-responder wiring and tests keep finding it in `subviews`.
    private func installBackground() {
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            background = glass
        } else {
            // Spotlight's own look, as closely as AppKit gives it for free:
            // one wide translucent slab holding one line of large text, and
            // nothing else -- the leading glyph this had at first just read
            // as clutter and was removed.
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.cornerRadius
            effect.layer?.masksToBounds = true
            // A layer corner radius rounds the CONTENTS; the behind-window blur is
            // drawn to the view's own shape and stayed a full rectangle, so the
            // panel read as a rounded box sitting on a square backdrop.
            // Only maskImage reshapes the blur itself.
            effect.maskImage = Self.roundedMask
            // The hairline that keeps the panel from dissolving into a light
            // desktop -- Spotlight has one, and without it the blur alone leaves
            // no edge at all over pale backgrounds.
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            background = effect
        }
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
    }

    /// Spotlight's panel proportions -- wide, one row tall, softly rounded.
    static let panelSize = CGSize(width: 640, height: 64)
    static let cornerRadius: CGFloat = 20
    static let horizontalInset: CGFloat = 20
    /// Only used for speech sizing; the input panel's height is fixed.
    static let verticalInset: CGFloat = 12

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for TextInputBubbleView")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !isShowingMessage else { return }
        window?.makeFirstResponder(textField)
    }

    /// Read-only notice mode — F6's "워크스페이스 꺼져있음", agent_done
    /// summaries, the mute sulk. Nothing can be typed while a notice shows.
    ///
    /// This is the pet *speaking*, so it drops the Spotlight typography: the
    /// bar's 24pt single line is right for a capture field the user is aiming
    /// at, and wrong for a bubble the size of a sentence sitting over a
    /// character's head.
    func showMessage(_ text: String) {
        isShowingMessage = true
        textField.isEditable = false
        textField.isSelectable = false
        textField.font = Self.speechFont
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.alignment = .center
        textField.stringValue = text
        attachButton.isHidden = true
        window?.makeFirstResponder(nil)
    }

    /// Back to the editable input field. Fresh session, fresh state -- no
    /// attachment carries over from whatever the bubble last showed.
    func showInput() {
        isShowingMessage = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.font = Self.inputFont
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .natural
        attachButton.isHidden = false
        setAttachmentThumbnail(nil)
        textField.stringValue = ""
        window?.makeFirstResponder(textField)
    }

    /// Big enough to be the only thing in the Spotlight panel.
    static let inputFont = NSFont.systemFont(ofSize: 24, weight: .regular)
    /// Speech is read at a glance beside the pet, not aimed at.
    static let speechFont = NSFont.systemFont(ofSize: 15, weight: .regular)

    /// A speech bubble is the size of what was said. Wraps past
    /// `speechMaxWidth` rather than growing into another Spotlight bar.
    static let speechMaxWidth: CGFloat = 300

    static func speechSize(for text: String) -> CGSize {
        let available = speechMaxWidth - horizontalInset * 2
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: available, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: speechFont]
        )
        return CGSize(
            width: min(speechMaxWidth, ceil(bounds.width) + horizontalInset * 2),
            height: max(44, ceil(bounds.height) + verticalInset * 2)
        )
    }

    private func configureTextField() {
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        // Big enough to be the only thing in the panel, like Spotlight's.
        textField.font = Self.inputFont
        textField.placeholderString = Self.placeholder
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textFieldLeadingWithoutThumbnail,
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// F14: a trailing capture button, and a
    /// leading thumbnail that only appears once something's been captured --
    /// hidden by default so the panel stays the same plain single line it
    /// was before this.
    private func configureAttachmentViews() {
        attachButton.bezelStyle = .regularSquare
        attachButton.isBordered = false
        attachButton.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: Strings.text(.bubbleCapturePrompt))
        attachButton.imageScaling = .scaleProportionallyUpOrDown
        attachButton.contentTintColor = .secondaryLabelColor
        attachButton.target = self
        attachButton.action = #selector(handleAttachButton)
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attachButton)

        thumbnailView.isHidden = true
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        let removeGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRemoveAttachment))
        thumbnailView.addGestureRecognizer(removeGesture)
        addSubview(thumbnailView)

        NSLayoutConstraint.activate([
            attachButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            attachButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 22),
            attachButton.heightAnchor.constraint(equalToConstant: 22),
            textField.trailingAnchor.constraint(equalTo: attachButton.leadingAnchor, constant: -Self.horizontalInset / 2),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
            thumbnailView.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
        ])
    }

    static let thumbnailSize: CGFloat = 40

    @objc private func handleAttachButton() {
        onAttachRequested?()
    }

    @objc private func handleRemoveAttachment() {
        onRemoveAttachment?()
    }

    /// The caller (AppDelegate) calls this once a capture completes (or is
    /// removed) -- the view has no opinion on when that happens, only how to
    /// show the result.
    func setAttachmentThumbnail(_ image: NSImage?) {
        thumbnailView.image = image
        thumbnailView.isHidden = image == nil
        textFieldLeadingWithoutThumbnail.isActive = image == nil
        textFieldLeadingWithThumbnail.isActive = image != nil
    }

    private static var placeholder: String { Strings.text(.bubblePlaceholder) }

    /// A rounded rectangle just big enough to hold both corners, stretched
    /// across whatever size the panel ends up -- the cap insets keep the
    /// corners crisp instead of scaling them with the panel. Rendered once:
    /// a fresh bubble view is built per show, and the mask never varies.
    private static let roundedMask: NSImage = {
        let radius = cornerRadius
        let side = radius * 2 + 1
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()
}

extension TextInputBubbleView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // A notice bubble has nothing to submit; let Escape still dismiss it.
        if isShowingMessage, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return false
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?(textField.stringValue)
            textField.stringValue = ""
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}
