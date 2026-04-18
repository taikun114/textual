import SwiftUI

// MARK: - Overview
//
// `TextSelectionInteraction` manages the text selection model lifecycle for multiple `Text` fragments.
//
// Selection is opt-in through the `textSelection` environment value. When enabled, the modifier
// observes text layout changes via `overlayTextLayoutCollection` and creates or updates a
// `TextSelectionModel`. The model is then passed to the platform-specific implementation
// (`PlatformTextSelectionInteraction`), which presents the appropriate selection UI for macOS
// or iOS. This separation keeps model management in shared code while platform interactions
// remain independent.

struct TextSelectionInteraction: ViewModifier {
  #if TEXTUAL_ENABLE_TEXT_SELECTION
    @Environment(\.textSelection) private var textSelection
    @Environment(TextSelectionCoordinator.self) private var coordinator: TextSelectionCoordinator?

    @State private var model = TextSelectionModel()
  #endif

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      if textSelection.allowsSelection {
          content
            .overlayTextLayoutCollection { layoutCollection in
              Color.clear
                .task(id: AnyTextLayoutCollection(layoutCollection)) {
                  do {
                     // ストリーミング完了時に複数のブロックが一斉に更新されるのを防ぐため、分散させる
                     let jitterSeconds = Double.random(in: 0...0.5)
                     try await Task.sleep(nanoseconds: UInt64((0.4 + jitterSeconds) * 1_000_000_000))
                     
                     guard textSelection.allowsSelection else { return }
                     
                     // メインActor上で実行するが、さらに次のRunLoopに逃がすことで
                     // SwiftUI の「同じフレームでの更新」エラーを物理的に回避する
                     await MainActor.run {
                       DispatchQueue.main.async {
                         if !Task.isCancelled {
                           model.setCoordinator(coordinator)
                           model.setLayoutCollection(layoutCollection)
                         }
                       }
                     }
                  } catch {
                    // キャンセル時は無視
                  }
                }
            }
          .modifier(PlatformTextSelectionInteraction(model: model))
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if TEXTUAL_ENABLE_TEXT_SELECTION
  extension EnvironmentValues {
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @usableFromInline
    @Entry var textSelection: any TextSelectability.Type = DisabledTextSelectability.self
  }
#endif
