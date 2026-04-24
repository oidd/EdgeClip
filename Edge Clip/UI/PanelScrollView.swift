import AppKit
import SwiftUI

struct PanelScrollView<Content: View>: NSViewRepresentable {
    let resetToken: Int
    let onScroll: (CGFloat, CGFloat?) -> Void
    let externalScrollToken: Int
    let externalScrollDelta: CGFloat
    let documentHeight: CGFloat?
    let content: Content

    init(
        resetToken: Int,
        externalScrollToken: Int = 0,
        externalScrollDelta: CGFloat = 0,
        documentHeight: CGFloat? = nil,
        onScroll: @escaping (CGFloat, CGFloat?) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.resetToken = resetToken
        self.externalScrollToken = externalScrollToken
        self.externalScrollDelta = externalScrollDelta
        self.documentHeight = documentHeight
        self.onScroll = onScroll
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, documentHeight: documentHeight)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let documentView = FlippedPanelDocumentView()
        let hostingView = NSHostingView(rootView: content)
        context.coordinator.documentView = documentView
        context.coordinator.hostingView = hostingView

        documentView.addSubview(hostingView)
        scrollView.documentView = documentView

        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            context.coordinator.handleScroll(in: scrollView)
        }

        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            context.coordinator.updateLayout(in: scrollView, documentHeight: context.coordinator.documentHeight)
        }

        DispatchQueue.main.async {
            context.coordinator.updateLayout(in: scrollView, documentHeight: context.coordinator.documentHeight)
            context.coordinator.setIndicatorVisible(false, in: scrollView, animated: false)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.documentHeight = documentHeight
        context.coordinator.hostingView?.rootView = content
        context.coordinator.updateLayout(in: nsView, documentHeight: documentHeight)

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.hideWorkItem?.cancel()
            nsView.contentView.scroll(to: .zero)
            nsView.reflectScrolledClipView(nsView.contentView)
            context.coordinator.setIndicatorVisible(false, in: nsView, animated: false)
        }

        if context.coordinator.lastExternalScrollToken != externalScrollToken {
            context.coordinator.lastExternalScrollToken = externalScrollToken
            context.coordinator.applyExternalScroll(delta: externalScrollDelta, in: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.boundsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = coordinator.frameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        coordinator.hideWorkItem?.cancel()
    }

    final class Coordinator {
        fileprivate var hostingView: NSHostingView<Content>?
        fileprivate var documentView: FlippedPanelDocumentView?
        fileprivate var boundsObserver: NSObjectProtocol?
        fileprivate var frameObserver: NSObjectProtocol?
        fileprivate var hideWorkItem: DispatchWorkItem?
        fileprivate var lastResetToken: Int?
        fileprivate var onScroll: (CGFloat, CGFloat?) -> Void
        fileprivate var documentHeight: CGFloat?
        fileprivate var lastReportedOffset: CGFloat?
        fileprivate var pendingOffset: CGFloat?
        fileprivate var pendingPointerDocumentY: CGFloat?
        fileprivate var isScrollCallbackScheduled = false
        fileprivate var isIndicatorVisible = true
        fileprivate var lastExternalScrollToken: Int?
        fileprivate var lastLayoutWidth: CGFloat?
        fileprivate var lastVisibleHeight: CGFloat?
        fileprivate var lastContentHeight: CGFloat?
        fileprivate var lastDocumentHeight: CGFloat?

        init(onScroll: @escaping (CGFloat, CGFloat?) -> Void, documentHeight: CGFloat?) {
            self.onScroll = onScroll
            self.documentHeight = documentHeight
        }

        func updateLayout(in scrollView: NSScrollView, documentHeight: CGFloat?) {
            guard let hostingView, let documentView else { return }

            let targetWidth = max(
                scrollView.contentView.bounds.width,
                scrollView.contentSize.width,
                1
            )
            let visibleHeight = max(
                scrollView.contentView.bounds.height,
                scrollView.contentSize.height,
                1
            )

            let contentHeight: CGFloat
            let resolvedDocumentHeight: CGFloat
            if let documentHeight {
                contentHeight = max(documentHeight, 1)
                resolvedDocumentHeight = max(contentHeight, visibleHeight, 1)
            } else {
                scrollView.layoutSubtreeIfNeeded()
                scrollView.contentView.layoutSubtreeIfNeeded()
                hostingView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: visibleHeight)
                hostingView.layoutSubtreeIfNeeded()
                contentHeight = max(hostingView.fittingSize.height, 1)
                resolvedDocumentHeight = max(contentHeight, visibleHeight, 1)
            }

            let layoutMatchesPrevious =
                approximatelyEqual(lastLayoutWidth, targetWidth) &&
                approximatelyEqual(lastVisibleHeight, visibleHeight) &&
                approximatelyEqual(lastContentHeight, contentHeight) &&
                approximatelyEqual(lastDocumentHeight, resolvedDocumentHeight)

            guard !layoutMatchesPrevious else { return }

            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: contentHeight
            )
            documentView.frame = NSRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: resolvedDocumentHeight
            )
            lastLayoutWidth = targetWidth
            lastVisibleHeight = visibleHeight
            lastContentHeight = contentHeight
            lastDocumentHeight = resolvedDocumentHeight
        }

        private func approximatelyEqual(_ lhs: CGFloat?, _ rhs: CGFloat, tolerance: CGFloat = 0.5) -> Bool {
            guard let lhs else { return false }
            return abs(lhs - rhs) <= tolerance
        }

        func handleScroll(in scrollView: NSScrollView) {
            let offset = max(0, scrollView.contentView.bounds.origin.y)
            if lastReportedOffset != offset {
                lastReportedOffset = offset
                pendingOffset = offset
                pendingPointerDocumentY = currentMouseDocumentY(in: scrollView)
                scheduleScrollCallbackIfNeeded()
            }

            let isScrollable = (documentView?.frame.height ?? 0) > (scrollView.contentSize.height + 1)
            guard isScrollable else {
                setIndicatorVisible(false, in: scrollView, animated: true)
                return
            }

            setIndicatorVisible(true, in: scrollView, animated: true)
            hideWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.setIndicatorVisible(false, in: scrollView, animated: true)
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
        }

        private func scheduleScrollCallbackIfNeeded() {
            guard !isScrollCallbackScheduled else { return }
            isScrollCallbackScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScrollCallbackScheduled = false
                guard let offset = self.pendingOffset else { return }
                let pointerDocumentY = self.pendingPointerDocumentY
                self.pendingOffset = nil
                self.pendingPointerDocumentY = nil
                self.onScroll(offset, pointerDocumentY)
            }
        }

        private func currentMouseDocumentY(in scrollView: NSScrollView) -> CGFloat? {
            guard let window = scrollView.window, let documentView else { return nil }

            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let mouseInClipView = scrollView.contentView.convert(mouseInWindow, from: nil)
            guard scrollView.contentView.bounds.contains(mouseInClipView) else {
                return nil
            }

            let mouseInDocument = documentView.convert(mouseInWindow, from: nil)
            return mouseInDocument.y
        }

        func setIndicatorVisible(_ visible: Bool, in scrollView: NSScrollView, animated: Bool) {
            guard visible != isIndicatorVisible else { return }
            isIndicatorVisible = visible
            guard let scroller = scrollView.verticalScroller else { return }

            let apply = {
                scroller.alphaValue = visible ? 1 : 0
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = visible ? 0.12 : 0.25
                    apply()
                }
            } else {
                apply()
            }
        }

        func applyExternalScroll(delta: CGFloat, in scrollView: NSScrollView) {
            guard delta != 0 else { return }
            let visibleRect = scrollView.contentView.bounds
            let documentHeight = documentView?.frame.height ?? 0
            guard documentHeight > visibleRect.height + 1 else { return }
            let targetOffset = visibleRect.origin.y + delta
            let clampedOffset = min(max(0, targetOffset), max(0, documentHeight - visibleRect.height))
            guard abs(clampedOffset - visibleRect.origin.y) > 0.5 else { return }

            scrollView.contentView.scroll(to: CGPoint(x: 0, y: clampedOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class FlippedPanelDocumentView: NSView {
    override var isFlipped: Bool { true }
}
