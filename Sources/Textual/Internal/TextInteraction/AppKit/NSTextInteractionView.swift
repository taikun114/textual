#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import SwiftUI

  // MARK: - Overview
  //
  // `NSTextInteractionView` implements selection and link interaction on macOS.
  //
  // The view sits in an overlay above one or more rendered `Text` fragments. It uses
  // `TextSelectionModel` for hit testing and range manipulation, and it respects `exclusionRects`
  // so embedded scrollable regions continue to receive input events. Link taps are forwarded to
  // `openURL`.

  final class NSTextInteractionView: NSView {
    var model: TextSelectionModel
    var exclusionRects: [CGRect]
    var openURL: OpenURLAction

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private enum SelectionGranularity {
      case character, word, block
    }
    private var selectionGranularity: SelectionGranularity = .character
    private var anchorRange: TextRange?
    private var selectionAnchor: TextPosition?

    init(
      model: TextSelectionModel,
      exclusionRects: [CGRect],
      openURL: OpenURLAction
    ) {
      self.model = model
      self.exclusionRects = exclusionRects
      self.openURL = openURL

      super.init(frame: .zero)
      self.wantsLayer = false
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      let localPoint = convert(point, from: superview)
      let isExcluded = exclusionRects.contains {
        $0.contains(localPoint)
      }

      if isExcluded {
        return nil
      }

      guard let result = super.hitTest(point) else { return nil }

      if result === self {
        // If the click is on us, check if it's actually over a scroller in a ScrollView behind us.
        // We traverse the window hierarchy to find views behind our current branch.
        let windowPoint = convert(point, to: nil)
        if isPointInScroller(windowPoint, startingAt: window?.contentView) {
          return nil
        }
      }

      return result
    }

    private func isPointInScroller(_ windowPoint: NSPoint, startingAt view: NSView?) -> Bool {
      guard let view = view else { return false }
      
      // Convert point to this view's system to check if it's within bounds
      let localPoint = view.convert(windowPoint, from: nil)
      if !view.visibleRect.contains(localPoint) {
        return false
      }
      
      // If this view is in our overlay's branch, skip it
      if view === self || self.isDescendant(of: view) {
        // But we still need to check sibling subviews that might be behind us
        for subview in view.subviews.reversed() {
          if subview === self || self.isDescendant(of: subview) {
            // Found the branch containing the overlay, skip it and check what's behind
            continue
          }
          if isPointInScroller(windowPoint, startingAt: subview) {
            return true
          }
        }
        return false
      }
      
      // If it's a scroller or part of a scroller, we found it
      if view is NSScroller || view.enclosingScrollView?.horizontalScroller === view || view.enclosingScrollView?.verticalScroller === view {
        return true
      }
      
      // Check subviews (top-most first)
      for subview in view.subviews.reversed() {
        if isPointInScroller(windowPoint, startingAt: subview) {
          return true
        }
      }
      
      return false
    }

    override func mouseDown(with event: NSEvent) {
      window?.makeFirstResponder(self)
      let location = convert(event.locationInWindow, from: nil)

      switch event.clickCount {
      case 1:
        if let url = model.url(for: location) {
          openURL(url)
        } else {
          resetSelection()
        }
        if let position = model.closestPosition(to: location) {
          selectionGranularity = .character
          anchorRange = TextRange(start: position, end: position)
        }
      case 2:
        if let position = model.closestPosition(to: location),
          let range = model.wordRange(for: position)
        {
          selectionGranularity = .word
          anchorRange = range
          model.selectedRange = range
        }
      case 3:
        if let position = model.closestPosition(to: location),
          let range = model.blockRange(for: position)
        {
          selectionGranularity = .block
          anchorRange = range
          model.selectedRange = range
        }
      default:
        break
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard let anchorRange else {
        return
      }

      let location = convert(event.locationInWindow, from: nil)

      guard let currentPosition = model.closestPosition(to: location) else {
        return
      }

      switch selectionGranularity {
      case .character:
        model.selectedRange = TextRange(from: anchorRange.start, to: currentPosition)
      case .word:
        if let currentWordRange = model.wordRange(for: currentPosition) {
          model.selectedRange = TextRange(
            start: min(anchorRange.start, currentWordRange.start),
            end: max(anchorRange.end, currentWordRange.end))
        }
      case .block:
        if let currentBlockRange = model.blockRange(for: currentPosition) {
          model.selectedRange = TextRange(
            start: min(anchorRange.start, currentBlockRange.start),
            end: max(anchorRange.end, currentBlockRange.end))
        }
      }

      autoscroll(with: event)

      // Ensure the current selection position is visible in any supporting scroll views
      let mouseWindowLocation = event.locationInWindow
      if let scrollView = findHorizontalScrollView(atY: mouseWindowLocation.y) {
        scrollView.documentView?.autoscroll(with: event)
      }
    }

    private func findHorizontalScrollView(atY windowY: CGFloat) -> NSScrollView? {
      func search(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView, sv !== self.enclosingScrollView {
          // Window座標系でスクロールビューのY座標範囲に一致するかチェック
          let rect = sv.convert(sv.bounds, to: nil)
          // marginを持たせて判定
          if windowY >= rect.minY - 10 && windowY <= rect.maxY + 10 {
            return sv
          }
        }
        for subview in view.subviews {
          if let found = search(in: subview) {
            return found
          }
        }
        return nil
      }
      return search(in: window?.contentView ?? self)
    }

    override func scrollWheel(with event: NSEvent) {
      // Find the view behind us
      let isHidden = self.isHidden
      self.isHidden = true
      let viewBehind = window?.contentView?.hitTest(event.locationInWindow)
      self.isHidden = isHidden

      if let scrollView = viewBehind as? NSScrollView ?? viewBehind?.enclosingScrollView,
        scrollView !== self.enclosingScrollView
      {
        scrollView.scrollWheel(with: event)
      } else {
        super.scrollWheel(with: event)
      }
    }

    override func mouseUp(with event: NSEvent) {
      anchorRange = nil
    }

    override func rightMouseDown(with event: NSEvent) {
      let location = convert(event.locationInWindow, from: nil)
      updateSelectionForContextMenu(at: location)

      NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      let location = convert(event.locationInWindow, from: nil)
      updateSelectionForContextMenu(at: location)

      return makeContextMenu()
    }

    override func selectAll(_ sender: Any?) {
      model.selectedRange = TextRange(start: model.startPosition, end: model.endPosition)
    }

    override func keyDown(with event: NSEvent) {
      interpretKeyEvents([event])
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.position(from: position, offset: 1)
      }
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.position(from: position, offset: -1)
      }
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
      modifySelection { position, anchor in
        model.positionAbove(position, anchor: anchor)
      }
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
      modifySelection { position, anchor in
        model.positionBelow(position, anchor: anchor)
      }
    }

    override func moveWordRightAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.nextWord(from: position)
      }
    }

    override func moveWordLeftAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.previousWord(from: position)
      }
    }

    override func moveParagraphBackwardAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.blockStart(for: position)
      }
    }

    override func moveParagraphForwardAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.blockEnd(for: position)
      }
    }

    private func updateSelectionForContextMenu(at location: CGPoint) {
      guard let position = model.closestPosition(to: location) else {
        resetSelection()
        return
      }

      if let selectedRange = model.selectedRange, selectedRange.contains(position) {
        // do nothing
        return
      }

      model.selectedRange = model.wordRange(for: position)
    }

    private func makeContextMenu() -> NSMenu {
      let contextMenu = NSMenu()

      guard let selectedRange = model.selectedRange, !selectedRange.isCollapsed else {
        return contextMenu
      }

      // Get the localized title for the share action
      let sharingPicker = NSSharingServicePicker(items: [])
      let shareActionTitle = sharingPicker.standardShareMenuItem.title

      // Get the localized title for the copy action
      let copyActionTitle =
        if let defaultMenu = NSTextView.defaultMenu,
          let copyAction = defaultMenu.items.first(where: { $0.action == #selector(copy(_:)) })
        {
          copyAction.title
        } else {
          NSLocalizedString("Copy", bundle: .main, comment: "")
        }

      contextMenu.addItem(
        .init(
          title: shareActionTitle,
          action: #selector(share(_:)),
          keyEquivalent: ""
        )
      )
      contextMenu.addItem(.separator())
      contextMenu.addItem(
        .init(
          title: copyActionTitle,
          action: #selector(copy(_:)),
          keyEquivalent: ""
        )
      )

      return contextMenu
    }

    private func modifySelection(
      _ transform: (_ position: TextPosition, _ anchor: TextPosition) -> TextPosition?
    ) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      // set anchor on first move
      selectionAnchor = selectionAnchor ?? selectedRange.start

      guard let selectionAnchor else {
        return
      }

      // modify the non-anchor end of the selection
      let position =
        selectionAnchor == selectedRange.start
        ? selectedRange.end
        : selectedRange.start

      guard let newPosition = transform(position, selectionAnchor) else {
        return
      }
      model.selectedRange = TextRange(from: selectionAnchor, to: newPosition)

      // scroll to make the new position visible
      let caretRect = model.caretRect(for: newPosition)
      scrollToVisible(caretRect)
    }

    private func resetSelection() {
      model.selectedRange = nil
      selectionAnchor = nil
    }

    @objc private func share(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let transferableText = TransferableText(attributedString: attributedText)
      let itemProvider = NSItemProvider(object: transferableText)

      let sharingPicker = NSSharingServicePicker(items: [itemProvider])
      let rect =
        model.selectionRects(for: selectedRange)
        .last?.rect.integral ?? .zero

      sharingPicker.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    @objc private func copy(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()

      let formatter = Formatter(attributedText)
      pasteboard.setString(formatter.plainText(), forType: .string)
      pasteboard.setString(formatter.html(), forType: .html)
    }
  }

  extension NSTextInteractionView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
      switch item.action {
      case #selector(selectAll(_:)):
        return model.hasText
      case #selector(copy(_:)):
        guard let selectedRange = model.selectedRange else {
          return false
        }
        return !selectedRange.isCollapsed
      case #selector(moveRightAndModifySelection(_:)),
        #selector(moveLeftAndModifySelection(_:)),
        #selector(moveUpAndModifySelection(_:)),
        #selector(moveDownAndModifySelection(_:)),
        #selector(moveWordRightAndModifySelection(_:)),
        #selector(moveWordLeftAndModifySelection(_:)),
        #selector(moveParagraphBackwardAndModifySelection(_:)),
        #selector(moveParagraphForwardAndModifySelection(_:)):
        return model.selectedRange != nil
      default:
        return true
      }
    }
  }
#endif
