#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI

  extension UITextInteractionView: UITextInput {
    var hasText: Bool {
      model.hasText
    }

    func insertText(_: String) {
      // Do nothing
    }

    func deleteBackward() {
      // Do nothing
    }

    func text(in range: UITextRange) -> String? {
      guard let rangeBox = range as? TextRangeBox else { return nil }
      return model.text(in: rangeBox.wrappedValue)
    }

    func replace(_ range: UITextRange, withText text: String) {
      // Do nothing
    }

    var selectedTextRange: UITextRange? {
      get { model.selectedRange.map(TextRangeBox.init) }
      set {
        let rangeBox = newValue as? TextRangeBox
        let newRange = rangeBox?.wrappedValue
        
#if os(visionOS)
        if let range = newRange {
          if let anchor = selectionAnchor {
            // Expand the range from anchor to the new range's edges
            let start = Swift.min(anchor, range.start)
            let end = Swift.max(anchor, range.end)
            model.selectedRange = TextRange(start: start, end: end)
          } else {
            // First selection in this interaction, set the anchor
            selectionAnchor = range.start
            model.selectedRange = range
          }
        } else {
          selectionAnchor = nil
          model.selectedRange = nil
        }
#else
        model.selectedRange = newRange
#endif
        logger.debug("selectedTextRange = \(String(describing: newValue))")
      }
    }

    var markedTextRange: UITextRange? {
      nil
    }

    var markedTextStyle: [NSAttributedString.Key: Any]? {
      get { nil }
      set {}
    }

    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
      // Do nothing
    }

    func unmarkText() {
      // Do nothing
    }

    var beginningOfDocument: UITextPosition {
      TextPositionBox(model.startPosition)
    }

    var endOfDocument: UITextPosition {
      TextPositionBox(model.endPosition)
    }

    func textRange(
      from fromPosition: UITextPosition,
      to toPosition: UITextPosition
    ) -> UITextRange? {
      guard
        let from = fromPosition as? TextPositionBox,
        let to = toPosition as? TextPositionBox
      else {
        return nil
      }
      return TextRangeBox(from: from, to: to)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
      guard let positionBox = position as? TextPositionBox else { return nil }
      return model.position(
        from: positionBox.wrappedValue,
        offset: offset
      ).map(TextPositionBox.init)
    }

    func position(
      from position: UITextPosition,
      in direction: UITextLayoutDirection,
      offset: Int
    ) -> UITextPosition? {
      guard let positionBox = position as? TextPositionBox else { return nil }
      let sign: Int
      switch direction {
      case .right, .down: sign = 1
      case .left, .up: sign = -1
      @unknown default: sign = 1
      }
      return model.position(
        from: positionBox.wrappedValue,
        offset: offset * sign
      ).map(TextPositionBox.init)
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
      guard
        let lhs = position as? TextPositionBox, let rhs = other as? TextPositionBox,
        lhs.wrappedValue != rhs.wrappedValue
      else {
        return .orderedSame
      }
      return lhs.wrappedValue < rhs.wrappedValue ? .orderedAscending : .orderedDescending
    }

    func offset(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> Int {
      guard
        let from = fromPosition as? TextPositionBox,
        let to = toPosition as? TextPositionBox
      else { return 0 }
      return model.offset(from: from.wrappedValue, to: to.wrappedValue)
    }

    var tokenizer: any UITextInputTokenizer {
      self
    }

    func position(
      within range: UITextRange,
      farthestIn direction: UITextLayoutDirection
    ) -> UITextPosition? {
      guard let rangeBox = range as? TextRangeBox else { return nil }
      switch direction {
      case .right, .down:
        return TextPositionBox(rangeBox.wrappedEnd)
      case .left, .up:
        return TextPositionBox(rangeBox.wrappedStart)
      @unknown default:
        return nil
      }
    }

    func characterRange(
      byExtending position: UITextPosition,
      in direction: UITextLayoutDirection
    ) -> UITextRange? {
      guard let pos = self.position(from: position, in: direction, offset: 1) else { return nil }
      guard let p1 = position as? TextPositionBox, let p2 = pos as? TextPositionBox else { return nil }
      
      if let currentRange = model.selectedRange {
        if p1.wrappedValue == currentRange.start {
          let minPos = Swift.min(p2.wrappedValue, currentRange.end)
          let maxPos = Swift.max(p2.wrappedValue, currentRange.end)
          return TextRangeBox(TextRange(start: minPos, end: maxPos))
        } else if p1.wrappedValue == currentRange.end {
          let minPos = Swift.min(currentRange.start, p2.wrappedValue)
          let maxPos = Swift.max(currentRange.start, p2.wrappedValue)
          return TextRangeBox(TextRange(start: minPos, end: maxPos))
        }
      }
      
      let minPos = Swift.min(p1.wrappedValue, p2.wrappedValue)
      let maxPos = Swift.max(p1.wrappedValue, p2.wrappedValue)
      return TextRangeBox(TextRange(start: minPos, end: maxPos))
    }

    func baseWritingDirection(
      for position: UITextPosition,
      in direction: UITextStorageDirection
    ) -> NSWritingDirection {
      // Not applicable for non-editable interaction mode?
      return .natural
    }

    func setBaseWritingDirection(_: NSWritingDirection, for _: UITextRange) {
      // Do nothing
    }

    func firstRect(for range: UITextRange) -> CGRect {
      guard let rangeBox = range as? TextRangeBox else { return .zero }
      return model.firstRect(for: rangeBox.wrappedValue)
    }

    func caretRect(for position: UITextPosition) -> CGRect {
      guard let positionBox = position as? TextPositionBox else { return .zero }
      return model.caretRect(for: positionBox.wrappedValue)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
      guard let rangeBox = range as? TextRangeBox else { return [] }
      return model.selectionRects(for: rangeBox.wrappedValue)
        .map(TextSelectionRectBox.init)
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
      model.closestPosition(to: point).map(TextPositionBox.init)
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
      guard let rangeBox = range as? TextRangeBox else { return nil }
      return model.closestPosition(
        to: point,
        within: rangeBox.wrappedValue
      ).map(TextPositionBox.init)
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
      model.characterRange(at: point).map(TextRangeBox.init)
    }

    var textInputView: UIView {
      self
    }

    var isEditable: Bool {
      false
    }

    func attributedText(in range: UITextRange) -> NSAttributedString {
      guard let rangeBox = range as? TextRangeBox else { return .init() }
      return model.attributedText(in: rangeBox.wrappedValue)
    }
  }
#endif
