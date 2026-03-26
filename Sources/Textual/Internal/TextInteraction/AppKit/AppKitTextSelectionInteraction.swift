#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import SwiftUI

  // MARK: - Overview
  //
  // `AppKitTextSelectionInteraction` presents the platform-specific text selection overlay for macOS.
  //
  // The modifier receives a `TextSelectionModel` and places it in the environment so selection highlights
  // and attachment dimming can access it. An overlay hosts `AppKitTextInteractionOverlay`, which wraps an
  // `NSView` that handles selection gestures and context menus. The modifier also manages cursor updates,
  // switching between I-beam and pointing hand based on hover position over text or links.

  typealias PlatformTextSelectionInteraction = AppKitTextSelectionInteraction

  struct AppKitTextSelectionInteraction: ViewModifier {
    @State private var cursorPushed = false
    @State private var interactiveFrames: [CGRect] = []

    private let model: TextSelectionModel

    init(model: TextSelectionModel) {
      self.model = model
    }

    func body(content: Content) -> some View {
      content
        .environment(model)
        .onPreferenceChange(InteractiveFrameKey.self) { frames in
          interactiveFrames = frames
        }
        .overlayPreferenceValue(OverflowFrameKey.self) { overflowFrames in
          AppKitTextInteractionOverlay(model: model, overflowFrames: overflowFrames)
            .onContinuousHover { phase in
              updateCursor(for: phase, model: model)
            }
        }
    }

    private func updateCursor(for phase: HoverPhase, model: TextSelectionModel) {
      switch phase {
      case .active(let location):
        let isInteractive = interactiveFrames.contains { $0.contains(location) }

        let cursor: NSCursor
        if isInteractive {
          cursor = .pointingHand
        } else if model.url(for: location) != nil {
          cursor = .pointingHand
        } else if model.isPointOverText(location) {
          cursor = .iBeam
        } else {
          cursor = .arrow
        }

        if !cursorPushed {
          cursor.push()
          cursorPushed = true
        } else {
          cursor.set()
        }
      case .ended:
        if cursorPushed {
          NSCursor.pop()
          cursorPushed = false
        }
      }
    }
  }
#endif
