import AppKit
import NotecastCore
import QuartzCore

/// Visual 6×2 grid of clickable background theme swatches displayed directly inside Settings.
@MainActor
final class BackgroundPaletteView: NSView {
    var selectedStyle: SurfaceStyle = .charcoal {
        didSet {
            updateSelection()
        }
    }

    var onSelectStyle: ((SurfaceStyle) -> Void)?

    private var swatchButtons: [SurfaceStyle: BackgroundSwatchButton] = [:]
    private let captionLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let allStyles = SurfaceStyle.allCases
        let columns = 6

        let rowsStack = NSStackView()
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8

        var index = 0
        while index < allStyles.count {
            let end = min(index + columns, allStyles.count)
            let rowStyles = Array(allStyles[index..<end])

            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 8

            for style in rowStyles {
                let swatch = BackgroundSwatchButton(style: style)
                swatch.onClick = { [weak self] chosen in
                    self?.selectedStyle = chosen
                    self?.onSelectStyle?(chosen)
                }
                swatchButtons[style] = swatch
                rowStack.addArrangedSubview(swatch)
            }

            rowsStack.addArrangedSubview(rowStack)
            index = end
        }

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor

        let container = NSStackView(views: [rowsStack, captionLabel])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6

        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateSelection() {
        for (style, button) in swatchButtons {
            button.isSelectedSwatch = (style == selectedStyle)
        }
        let suffix = selectedStyle.isOpaque ? "" : " (Adjustable opacity)"
        captionLabel.stringValue = "\(selectedStyle.displayName)\(suffix)"
    }
}

@MainActor
private final class BackgroundSwatchButton: NSView {
    let style: SurfaceStyle
    var onClick: ((SurfaceStyle) -> Void)?

    var isSelectedSwatch = false {
        didSet {
            updateBorder()
        }
    }

    private let headerStrip = NSView()
    private let hudGradientLayer = CAGradientLayer()

    init(style: SurfaceStyle) {
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 26))
        setupSwatch()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 38, height: 26)
    }

    override func layout() {
        super.layout()
        hudGradientLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(style)
    }

    private func setupSwatch() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        toolTip = style.displayName
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(style.displayName)

        if let bodyColor = style.backgroundColor {
            layer?.backgroundColor = bodyColor.cgColor

            headerStrip.translatesAutoresizingMaskIntoConstraints = false
            headerStrip.wantsLayer = true
            headerStrip.layer?.backgroundColor = (style.headerBackgroundColor ?? bodyColor).cgColor
            addSubview(headerStrip)

            let divider = NSView()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.wantsLayer = true
            divider.layer?.backgroundColor = style.calmSeparatorColor.cgColor
            addSubview(divider)

            // Tiny preview text line hint inside swatch for quick light/dark contrast preview
            let line1 = NSView()
            line1.translatesAutoresizingMaskIntoConstraints = false
            line1.wantsLayer = true
            line1.layer?.cornerRadius = 1
            let textAlphaColor: NSColor = style.isLight
                ? NSColor.black.withAlphaComponent(0.45)
                : NSColor.white.withAlphaComponent(0.50)
            line1.layer?.backgroundColor = textAlphaColor.cgColor
            addSubview(line1)

            let line2 = NSView()
            line2.translatesAutoresizingMaskIntoConstraints = false
            line2.wantsLayer = true
            line2.layer?.cornerRadius = 1
            line2.layer?.backgroundColor = textAlphaColor.withAlphaComponent(0.32).cgColor
            addSubview(line2)

            NSLayoutConstraint.activate([
                headerStrip.topAnchor.constraint(equalTo: topAnchor),
                headerStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
                headerStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
                headerStrip.heightAnchor.constraint(equalToConstant: 7),

                divider.topAnchor.constraint(equalTo: headerStrip.bottomAnchor),
                divider.leadingAnchor.constraint(equalTo: leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: trailingAnchor),
                divider.heightAnchor.constraint(equalToConstant: 1),

                line1.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
                line1.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                line1.widthAnchor.constraint(equalToConstant: 20),
                line1.heightAnchor.constraint(equalToConstant: 2),

                line2.topAnchor.constraint(equalTo: line1.bottomAnchor, constant: 3),
                line2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                line2.widthAnchor.constraint(equalToConstant: 13),
                line2.heightAnchor.constraint(equalToConstant: 2)
            ])
        } else {
            // Translucent HUD glass swatch
            hudGradientLayer.colors = [
                NSColor(srgbRed: 0.34, green: 0.42, blue: 0.54, alpha: 0.65).cgColor,
                NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.78).cgColor
            ]
            hudGradientLayer.startPoint = CGPoint(x: 0, y: 1)
            hudGradientLayer.endPoint = CGPoint(x: 1, y: 0)
            layer?.addSublayer(hudGradientLayer)

            let glassIcon = NSImageView()
            glassIcon.translatesAutoresizingMaskIntoConstraints = false
            glassIcon.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
            glassIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            glassIcon.contentTintColor = .white
            addSubview(glassIcon)

            NSLayoutConstraint.activate([
                glassIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
                glassIcon.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 26)
        ])

        updateBorder()
    }

    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelectedSwatch {
                layer?.borderWidth = 2.0
                layer?.borderColor = NSColor.controlAccentColor.cgColor
            } else {
                layer?.borderWidth = 1.0
                let subtleColor: NSColor = style.isLight
                    ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22)
                    : NSColor(white: 1.0, alpha: 0.22)
                layer?.borderColor = subtleColor.cgColor
            }
        }
    }
}
