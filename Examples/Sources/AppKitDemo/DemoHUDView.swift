import AppKit

/// A floating, translucent pill HUD displayed at the bottom-center of the window
/// during Demo Reel playback. Shows live step information and an Exit button.
@MainActor
final class DemoHUDView: NSVisualEffectView {
    var onExitRequested: (() -> Void)?
    var onTurntableToggleRequested: (() -> Void)?

    private let badgeLabel = NSTextField(labelWithString: "● REC REEL")
    private let stepLabel = NSTextField(labelWithString: "Step 1 of 9")
    private let titleLabel = NSTextField(labelWithString: "Standard PBR")
    private let subtitleLabel = NSTextField(labelWithString: "Physically-Based Rendering")
    private let turntableButton = NSButton()
    private let exitButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 20.0
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1.0

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12.0
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])

        // REC badge
        badgeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .systemRed
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(badgeLabel)

        // Separator
        let sep1 = NSBox()
        sep1.boxType = .separator
        sep1.translatesAutoresizingMaskIntoConstraints = false
        sep1.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep1.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(sep1)

        // Step number
        stepLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(stepLabel)

        // Separator
        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep2.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(sep2)

        // Title and Subtitle text stack
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1.0

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(titleLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(subtitleLabel)

        stack.addArrangedSubview(textStack)

        // Spacer to push action buttons
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        // Turntable button
        turntableButton.title = "🔄 Turntable: OFF [R]"
        turntableButton.bezelStyle = .inline
        turntableButton.controlSize = .small
        turntableButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        turntableButton.target = self
        turntableButton.action = #selector(onTurntableClicked)
        turntableButton.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(turntableButton)

        // Exit button
        exitButton.title = "Stop (Esc)"
        exitButton.bezelStyle = .inline
        exitButton.controlSize = .small
        exitButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        exitButton.target = self
        exitButton.action = #selector(onExitClicked)
        exitButton.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(exitButton)
    }

    @objc private func onTurntableClicked() {
        onTurntableToggleRequested?()
    }

    @objc private func onExitClicked() {
        onExitRequested?()
    }

    func setTurntableState(enabled: Bool) {
        turntableButton.title = enabled ? "🔄 Turntable: ON [R]" : "🔄 Turntable: OFF [R]"
        turntableButton.contentTintColor = enabled ? .systemTeal : .secondaryLabelColor
    }

    func update(step: Int, total: Int, title: String, subtitle: String) {
        stepLabel.stringValue = "\(step)/\(total)"
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
    }

    func present(in parentView: NSView) {
        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: -24),
            heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 520),
            widthAnchor.constraint(lessThanOrEqualToConstant: 740),
        ])

        alphaValue = 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 1.0
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.removeFromSuperview()
            }
        })
    }
}
