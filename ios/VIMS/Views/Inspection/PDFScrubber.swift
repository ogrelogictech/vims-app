import UIKit
import PDFKit

// Client Oct 16: the report preview (and the generated-PDF preview) gets a visible, draggable scroll thumb on the right
// edge for fast navigation through the pages, with a "Page X of N" bubble while it's dragged or the pages scroll.
// It tracks PDFView's own scroll view, so it follows normal scrolling, pinch-zoom, rotation and iPad window resizes.

/// PDF view + scrubber overlay. The overlay only takes touches on the thumb; everything else reaches the PDF.
final class ScrubbablePDFView: UIView {
    let pdfView = FitWidthPDFView()
    private let scrubber = PDFScrubberView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for v in [pdfView, scrubber] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        scrubber.pdfView = pdfView
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrubber.attachIfNeeded()
    }

    /// DEBUG review screenshots (-scrubTo F): scroll to fraction F and hold the dragged look (thumb + bubble).
    func demoScrub(to fraction: CGFloat) { scrubber.demoScrub(to: fraction) }
}

final class PDFScrubberView: UIView {
    weak var pdfView: PDFView?
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?

    private let thumb = ScrubThumb()
    private let bubble = UIView()
    private let bubbleLabel = UILabel()
    private var dragging = false
    private var dragStartTop: CGFloat = 0
    private var fadeWork: DispatchWorkItem?
    private var pinned = false

    private let thumbSize = CGSize(width: 28, height: 56)
    private let edgeInset: CGFloat = 5
    private let trackInset: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        thumb.backgroundColor = UIColor(hex: 0x2F5EC9)
        thumb.layer.cornerRadius = 14
        thumb.layer.cornerCurve = .continuous
        thumb.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        thumb.layer.borderWidth = 1.5
        thumb.layer.shadowColor = UIColor.black.cgColor
        thumb.layer.shadowOpacity = 0.35
        thumb.layer.shadowRadius = 4
        thumb.layer.shadowOffset = CGSize(width: 0, height: 1)
        let grip = UIStackView()
        grip.axis = .vertical
        grip.spacing = 4
        grip.isUserInteractionEnabled = false
        for _ in 0..<3 {
            let l = UIView()
            l.backgroundColor = .white
            l.layer.cornerRadius = 1
            l.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([l.widthAnchor.constraint(equalToConstant: 12), l.heightAnchor.constraint(equalToConstant: 2)])
            grip.addArrangedSubview(l)
        }
        grip.translatesAutoresizingMaskIntoConstraints = false
        thumb.addSubview(grip)
        NSLayoutConstraint.activate([grip.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
                                     grip.centerYAnchor.constraint(equalTo: thumb.centerYAnchor)])
        thumb.alpha = 0.75
        thumb.isHidden = true
        addSubview(thumb)

        bubble.backgroundColor = UIColor(hex: 0x101F45).withAlphaComponent(0.94)
        bubble.layer.cornerRadius = 9
        bubble.layer.cornerCurve = .continuous
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.3
        bubble.layer.shadowRadius = 5
        bubble.layer.shadowOffset = CGSize(width: 0, height: 1)
        bubble.alpha = 0
        bubble.isUserInteractionEnabled = false
        bubbleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        bubbleLabel.textColor = .white
        bubble.addSubview(bubbleLabel)
        addSubview(bubble)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        addGestureRecognizer(pan)

        thumb.isAccessibilityElement = true
        thumb.accessibilityLabel = "Page scroller"
        thumb.accessibilityHint = "Swipe up or down to change page, or drag to scroll quickly"
        thumb.accessibilityTraits = .adjustable
        thumb.onStep = { [weak self] forward in self?.step(forward) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Only the thumb (with a 44 pt+ touch area) takes touches; the rest of the overlay passes them to the PDF.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !thumb.isHidden else { return nil }
        let hit = thumb.frame.insetBy(dx: -12, dy: -6)
        return hit.contains(point) ? self : nil
    }

    /// PDFView builds its scroll view lazily; hook it once it exists (and again if PDFKit replaces it).
    func attachIfNeeded() {
        guard let pdfView else { return }
        let sv = Self.findScrollView(in: pdfView)
        if sv !== scrollView, let sv {
            scrollView = sv
            sv.showsVerticalScrollIndicator = false
            offsetObservation = sv.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.scrolled() }
            }
            sizeObservation = sv.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.positionThumb() }
            }
        }
        positionThumb()
    }

    private static func findScrollView(in v: UIView) -> UIScrollView? {
        for s in v.subviews {
            if let sv = s as? UIScrollView { return sv }
            if let sv = findScrollView(in: s) { return sv }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionThumb()
    }

    // MARK: geometry

    private var trackTop: CGFloat { trackInset }
    private var trackHeight: CGFloat { max(0, bounds.height - trackInset * 2 - thumbSize.height) }

    private var maxOffset: CGFloat {
        guard let sv = scrollView else { return 0 }
        let i = sv.adjustedContentInset
        return max(0, sv.contentSize.height + i.top + i.bottom - sv.bounds.height)
    }

    private var progress: CGFloat {
        guard let sv = scrollView, maxOffset > 0 else { return 0 }
        return min(1, max(0, (sv.contentOffset.y + sv.adjustedContentInset.top) / maxOffset))
    }

    private func positionThumb() {
        let scrollable = maxOffset > 1 && bounds.height > thumbSize.height * 2
        thumb.isHidden = !scrollable
        if !scrollable { bubble.alpha = 0; return }
        let top = dragging ? thumb.frame.minY : trackTop + progress * trackHeight
        thumb.frame = CGRect(x: bounds.width - thumbSize.width - edgeInset, y: top, width: thumbSize.width, height: thumbSize.height)
        layoutBubble()
        thumb.accessibilityValue = pageText
    }

    private func layoutBubble() {
        bubbleLabel.text = pageText
        bubbleLabel.sizeToFit()
        let w = bubbleLabel.bounds.width + 24, h: CGFloat = 34
        bubble.frame = CGRect(x: thumb.frame.minX - 10 - w, y: thumb.frame.midY - h / 2, width: w, height: h)
        bubbleLabel.center = CGPoint(x: w / 2, y: h / 2)
    }

    // MARK: page

    private var pageCount: Int { pdfView?.document?.pageCount ?? 0 }

    /// The page at the middle of the view; the ends of the track read page 1 and the last page.
    private var pageIndex: Int {
        guard let pdfView, let doc = pdfView.document, doc.pageCount > 0 else { return 0 }
        if progress <= 0.001 { return 0 }
        if progress >= 0.999 { return doc.pageCount - 1 }
        let mid = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        guard let page = pdfView.page(for: mid, nearest: true) else { return 0 }
        return max(0, doc.index(for: page))
    }

    private var pageText: String { pageCount > 0 ? "Page \(pageIndex + 1) of \(pageCount)" : "" }

    // MARK: activity

    private func scrolled() {
        positionThumb()
        guard let sv = scrollView, !thumb.isHidden else { return }
        if dragging || sv.isDragging || sv.isDecelerating { showActive() }
    }

    private func showActive() {
        fadeWork?.cancel()
        layoutBubble()
        UIView.animate(withDuration: 0.15) {
            self.thumb.alpha = 1
            self.bubble.alpha = 1
        }
        guard !dragging, !pinned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.dragging else { return }
            UIView.animate(withDuration: 0.35) {
                self.thumb.alpha = 0.75
                self.bubble.alpha = 0
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let sv = scrollView, maxOffset > 0 else { return }
        switch g.state {
        case .began:
            pinned = false
            dragging = true
            dragStartTop = thumb.frame.minY
            sv.setContentOffset(sv.contentOffset, animated: false)   // stops any deceleration
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showActive()
        case .changed:
            let top = min(trackTop + trackHeight, max(trackTop, dragStartTop + g.translation(in: self).y))
            thumb.frame.origin.y = top
            let p = trackHeight > 0 ? (top - trackTop) / trackHeight : 0
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: p * maxOffset - sv.adjustedContentInset.top), animated: false)
            layoutBubble()
            thumb.accessibilityValue = pageText
        default:
            dragging = false
            positionThumb()
            showActive()
        }
    }

    /// VoiceOver adjustable: one page per swipe.
    private func step(_ forward: Bool) {
        guard let pdfView, let doc = pdfView.document else { return }
        let i = min(doc.pageCount - 1, max(0, pageIndex + (forward ? 1 : -1)))
        if let page = doc.page(at: i) { pdfView.go(to: page) }
        positionThumb()
        showActive()
        UIAccessibility.post(notification: .announcement, argument: pageText)
    }

    func demoScrub(to fraction: CGFloat) {
        attachIfNeeded()
        guard let sv = scrollView, maxOffset > 0 else { return }
        pinned = true
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: min(1, max(0, fraction)) * maxOffset - sv.adjustedContentInset.top), animated: false)
        positionThumb()
        showActive()
    }
}

private final class ScrubThumb: UIView {
    var onStep: ((Bool) -> Void)?
    override func accessibilityIncrement() { onStep?(true) }
    override func accessibilityDecrement() { onStep?(false) }
}
