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
                .task(id: layoutCollection.identity) {
                  // 選択が許可されていない（ストリーミング中など）場合は、
                  // レイアウト情報の同期処理自体をスキップして負荷を下げる
                  guard textSelection.allowsSelection else { return }

                  do {
                    // レイアウト計算が落ち着くのを待つための短いディレイ。
                    // ストリーミング完了時の集中を避けるため、即時更新を避ける
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    
                    if !Task.isCancelled {
                      await MainActor.run {
                        // 文字選択が無効化されていないか再確認
                        guard !Task.isCancelled, textSelection.allowsSelection else { return }
                        
                        // setLayoutCollection内部で自動的に重複チェックが行われるため
                        // ここでは無条件に呼び出して、モデル側に判断を任せる
                        model.setCoordinator(coordinator)
                        model.setLayoutCollection(layoutCollection)
                      }
                    }
                  } catch {
                     // キャンセル
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
