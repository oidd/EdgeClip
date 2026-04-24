import AppKit

private enum MenuBarStatusItemLayout {
    static let horizontalInset: CGFloat = 4
    static let trailingInset: CGFloat = 8
    static let iconSize: CGFloat = 19
    static let iconOnlyLength: CGFloat = 31
    static let iconTextSpacing: CGFloat = 6
    static let titleFont = NSFont.menuBarFont(ofSize: 0)
    static let titleSlotWidth: CGFloat = {
        let probeText = String(repeating: "测", count: 12)
        return ceil((probeText as NSString).size(withAttributes: [.font: titleFont]).width)
    }()
    static let titledLength: CGFloat =
        horizontalInset + iconSize + iconTextSpacing + titleSlotWidth + trailingInset
}

private final class NonInteractiveStatusIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class NonInteractiveStatusTitleField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class MenuBarStatusItemContentView: NSView {
    private let iconView = NonInteractiveStatusIconView()
    private let titleField = NonInteractiveStatusTitleField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleField.font = MenuBarStatusItemLayout.titleFont
        titleField.alignment = .center
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage, title: String?, highlighted: Bool) {
        iconView.image = image
        titleField.stringValue = title ?? ""
        titleField.isHidden = titleField.stringValue.isEmpty
        applyColors(highlighted: highlighted)
        needsLayout = true
    }

    func setHighlighted(_ highlighted: Bool) {
        applyColors(highlighted: highlighted)
    }

    override func layout() {
        super.layout()

        let iconY = floor((bounds.height - MenuBarStatusItemLayout.iconSize) / 2)
        iconView.frame = NSRect(
            x: MenuBarStatusItemLayout.horizontalInset,
            y: iconY,
            width: MenuBarStatusItemLayout.iconSize,
            height: MenuBarStatusItemLayout.iconSize
        )

        guard !titleField.isHidden else {
            titleField.frame = .zero
            return
        }

        let titleX = iconView.frame.maxX + MenuBarStatusItemLayout.iconTextSpacing
        let titleWidth = min(
            MenuBarStatusItemLayout.titleSlotWidth,
            max(0, bounds.width - titleX - MenuBarStatusItemLayout.trailingInset)
        )
        let titleHeight = min(bounds.height, ceil(titleField.intrinsicContentSize.height))
        let titleY = floor((bounds.height - titleHeight) / 2)

        titleField.frame = NSRect(
            x: titleX,
            y: titleY,
            width: titleWidth,
            height: titleHeight
        )
    }

    private func applyColors(highlighted: Bool) {
        let color = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        iconView.contentTintColor = color
        titleField.textColor = color
    }
}

@MainActor
final class MenuBarStatusItemController: NSObject {
    enum LeftClickBehavior {
        case togglePanel
        case showMenu
    }

    private static let assetImageName = NSImage.Name("MenuBarStatusIcon")

    var onLeftClick: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var contentView: MenuBarStatusItemContentView?
    private var leftClickBehavior: LeftClickBehavior = .togglePanel

    var buttonScreenFrame: CGRect? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }

        return window.convertToScreen(button.frame)
    }

    func update(title: String?, leftClickBehavior: LeftClickBehavior) {
        self.leftClickBehavior = leftClickBehavior
        installIfNeeded()
        applyTitle(title)
    }

    func uninstall() {
        statusMenu = nil
        contentView = nil

        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func contains(point: CGPoint) -> Bool {
        buttonScreenFrame?.contains(point) == true
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            handlePrimaryClick()
            return
        }

        switch event.type {
        case .rightMouseUp:
            openMenu()
        case .leftMouseUp:
            handlePrimaryClick()
        default:
            handlePrimaryClick()
        }
    }

    @objc
    private func openSettingsFromMenu(_ sender: Any?) {
        onOpenSettings?()
    }

    @objc
    private func quitFromMenu(_ sender: Any?) {
        onQuit?()
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: MenuBarStatusItemLayout.iconOnlyLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.title = ""
        button.font = MenuBarStatusItemLayout.titleFont
        installContentView(in: button)
        item.length = MenuBarStatusItemLayout.iconOnlyLength
    }

    private func applyTitle(_ title: String?) {
        guard let statusItem, let button = statusItem.button else { return }
        installContentView(in: button)

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        contentView?.update(
            image: Self.makeTemplateImage(),
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            highlighted: false
        )
        statusItem.length = trimmedTitle.isEmpty
            ? MenuBarStatusItemLayout.iconOnlyLength
            : MenuBarStatusItemLayout.titledLength
        button.needsLayout = true
        button.layoutSubtreeIfNeeded()
        button.displayIfNeeded()
    }

    private func popUpStatusMenu() {
        guard let button = statusItem?.button else { return }
        let menu = statusMenu ?? makeStatusMenu()
        statusMenu = menu
        button.highlight(true)
        contentView?.setHighlighted(true)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: max(0, button.bounds.height - 4)),
            in: button
        )
        button.highlight(false)
        contentView?.setHighlighted(false)
    }

    private func handlePrimaryClick() {
        switch leftClickBehavior {
        case .togglePanel:
            onLeftClick?()
        case .showMenu:
            openMenu()
        }
    }

    private func openMenu() {
        onMenuWillOpen?()
        popUpStatusMenu()
    }

    private func installContentView(in button: NSStatusBarButton) {
        guard contentView == nil else { return }

        let view = MenuBarStatusItemContentView()
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        contentView = view
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(
            title: AppLocalization.localized("偏好设置…"),
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: AppLocalization.localized("退出 Edge Clip"),
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private static func makeTemplateImage() -> NSImage {
        if let image = NSImage(named: assetImageName)?.copy() as? NSImage {
            image.isTemplate = true
            image.size = NSSize(width: 22, height: 22)
            return image
        }

        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let backRect = NSRect(x: 2.1, y: 4.5, width: 12.3, height: 12.9)
            let frontRect = NSRect(x: 6.4, y: 2.1, width: 12.3, height: 12.9)

            let backPath = NSBezierPath(roundedRect: backRect, xRadius: 3.0, yRadius: 3.0)
            let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: 3.0, yRadius: 3.0)

            backPath.lineWidth = 2.4
            frontPath.lineWidth = 2.4
            NSColor.black.setStroke()
            backPath.stroke()
            frontPath.stroke()
            return true
        }

        image.isTemplate = true
        return image
    }
}
