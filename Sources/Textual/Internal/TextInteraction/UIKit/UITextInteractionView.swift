#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI
  import os
  import UniformTypeIdentifiers

  // MARK: - Overview
  //
  // `UITextInteractionView` implements selection and link interaction on iOS-family platforms.
  //
  // The view sits in an overlay above one or more rendered `Text` fragments. It uses
  // `TextSelectionModel` to translate touch locations into URLs and selection ranges, and it
  // respects `exclusionRects` so embedded scrollable regions can continue to handle gestures.
  // Selection UI is provided by `UITextInteraction` configured for non-editable content.

  final class UITextInteractionView: UIView {
    override var canBecomeFirstResponder: Bool {
      true
    }

    var model: TextSelectionModel
    var exclusionRects: [CGRect]
    var openURL: OpenURLAction

    weak var inputDelegate: (any UITextInputDelegate)?

    let logger = Logger(category: .textInteraction)

    private(set) lazy var _tokenizer = UITextInputStringTokenizer(textInput: self)
    private let selectionInteraction: UITextInteraction

    private var codeBlockPanGesture: UIPanGestureRecognizer?
    private weak var targetScrollView: UIScrollView?
    private var initialContentOffset: CGPoint = .zero

    init(
      model: TextSelectionModel,
      exclusionRects: [CGRect],
      openURL: OpenURLAction
    ) {
      self.model = model
      self.exclusionRects = exclusionRects
      self.openURL = openURL
      self.selectionInteraction = UITextInteraction(for: .nonEditable)

      super.init(frame: .zero)
      self.backgroundColor = .clear

      setUp()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      for exclusionRect in exclusionRects {
        if exclusionRect.contains(point) {
          return false
        }
      }
      return super.point(inside: point, with: event)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      switch action {
      case #selector(copy(_:)), #selector(share(_:)):
        return !(model.selectedRange?.isCollapsed ?? true)
      default:
        return false
      }
    }

    override func copy(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let formatter = Formatter(attributedText)

      UIPasteboard.general.setItems(
        [
          [
            UTType.plainText.identifier: formatter.plainText(),
            UTType.html.identifier: formatter.html(),
          ]
        ]
      )
    }

    private func setUp() {
      model.selectionWillChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionWillChange(self)
      }
      model.selectionDidChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionDidChange(self)
        self.autoScrollForSelectionIfNeeded()
      }

      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      addGestureRecognizer(tapGesture)

      let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleCodeBlockPan(_:)))
      panGesture.delegate = self
      addGestureRecognizer(panGesture)
      self.codeBlockPanGesture = panGesture

      selectionInteraction.textInput = self
      selectionInteraction.delegate = self

      for gesture in selectionInteraction.gesturesForFailureRequirements {
        tapGesture.require(toFail: gesture)
        panGesture.require(toFail: gesture)
      }

      addInteraction(selectionInteraction)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
      let location = gesture.location(in: self)
      if let url = model.url(for: location) {
        openURL(url)
      } else {
        model.selectedRange = nil
      }
    }

    @objc private func share(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let itemSource = TextActivityItemSource(attributedString: attributedText)

      let activityViewController = UIActivityViewController(
        activityItems: [itemSource],
        applicationActivities: nil
      )

      if let popover = activityViewController.popoverPresentationController {
        let rect =
          model.selectionRects(for: selectedRange)
          .last?.rect.integral ?? .zero
        popover.sourceView = self
        popover.sourceRect = rect
      }

      if let windowScene = window?.windowScene,
        let viewController = windowScene.windows.first?.rootViewController
      {
        viewController.present(activityViewController, animated: true)
      }
    }

    @objc private func handleCodeBlockPan(_ gesture: UIPanGestureRecognizer) {
      guard let sv = targetScrollView else { return }

      switch gesture.state {
      case .began:
        initialContentOffset = sv.contentOffset
        sv.layer.removeAllAnimations()
      case .changed:
        let translation = gesture.translation(in: self)
        var newOffset = initialContentOffset
        newOffset.x -= translation.x
        let maxOffsetX = max(0, sv.contentSize.width - sv.bounds.width)
        newOffset.x = max(0, min(newOffset.x, maxOffsetX))
        sv.contentOffset = newOffset
      case .ended, .cancelled:
        let velocity = gesture.velocity(in: self)
        if abs(velocity.x) > 50 {
          var targetX = sv.contentOffset.x - (velocity.x * 0.2)
          let maxOffsetX = max(0, sv.contentSize.width - sv.bounds.width)
          targetX = max(0, min(targetX, maxOffsetX))
          UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            sv.contentOffset = CGPoint(x: targetX, y: sv.contentOffset.y)
          }
        }
        targetScrollView = nil
      default:
        break
      }
    }

    private func autoScrollForSelectionIfNeeded() {
      guard let selectedRange = model.selectedRange else { return }
      let startRect = model.caretRect(for: selectedRange.start)
      let endRect = model.caretRect(for: selectedRange.end)

      for rect in [startRect, endRect] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let sv = findHorizontalScrollView(atLocation: center) {
          let localRect = sv.convert(rect, from: self)
          // Expand rect slightly to ensure text isn't flush with edge
          let paddedRect = localRect.insetBy(dx: -16, dy: 0)
          sv.scrollRectToVisible(paddedRect, animated: false)
        }
      }
    }

    private func findHorizontalScrollView(atLocation point: CGPoint) -> UIScrollView? {
      let windowPoint = self.convert(point, to: nil)
      func search(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView, !sv.isHidden {
          if sv.contentSize.width > sv.bounds.width {
            let rect = sv.convert(sv.bounds, to: nil)
            if windowPoint.y >= rect.minY - 10 && windowPoint.y <= rect.maxY + 10 {
              return sv
            }
          }
        }
        for subview in view.subviews {
          if let found = search(in: subview) {
            return found
          }
        }
        return nil
      }
      return search(in: window?.rootViewController?.view ?? self)
    }
  }

  extension UITextInteractionView: UITextInteractionDelegate {
    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
      logger.debug("interactionShouldBegin(at: \(point.logDescription)) -> true")
      return true
    }

    func interactionWillBegin(_ interaction: UITextInteraction) {
      logger.debug("interactionWillBegin")
      _ = self.becomeFirstResponder()
    }

    func interactionDidEnd(_ interaction: UITextInteraction) {
      logger.debug("interactionDidEnd")
    }
  }

  extension UITextInteractionView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === codeBlockPanGesture, let pan = gestureRecognizer as? UIPanGestureRecognizer {
        let velocity = pan.velocity(in: self)
        if abs(velocity.x) > abs(velocity.y) {
          let location = pan.location(in: self)
          if let sv = findHorizontalScrollView(atLocation: location) {
            targetScrollView = sv
            return true
          }
        }
        return false
      }
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      return false
    }
  }

  extension Logger.Textual.Category {
    fileprivate static let textInteraction = Self(rawValue: "textInteraction")
  }
#endif
