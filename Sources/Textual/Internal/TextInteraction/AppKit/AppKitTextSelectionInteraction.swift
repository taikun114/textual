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
    private let model: TextSelectionModel

    init(model: TextSelectionModel) {
      self.model = model
    }

    func body(content: Content) -> some View {
      content
        .environment(model)
        .overlayPreferenceValue(OverflowFrameKey.self) { overflowFrames in
          AppKitTextInteractionOverlay(model: model, overflowFrames: overflowFrames)
        }
    }
  }
#endif
