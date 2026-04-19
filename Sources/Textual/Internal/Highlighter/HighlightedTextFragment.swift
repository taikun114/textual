import SwiftUI

// MARK: - Overview
//
// HighlightedTextFragment displays syntax-highlighted code using a two-phase approach.
// Tokenization runs asynchronously and is keyed by content, while highlighting runs
// synchronously on token or environment changes (theme, color scheme, dynamic type).
//
// The presentationIntent is preserved after highlighting so pasteboard formatters can
// reconstruct the block structure when copying code.

struct HighlightedTextFragment: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @Environment(\.isSyntaxHighlightingEnabled) private var isSyntaxHighlightingEnabled

  @State private var model = Model()

  private let content: AttributedSubstring
  private let languageHint: String?
  private let theme: StructuredText.HighlighterTheme

  init(
    _ content: AttributedSubstring,
    languageHint: String?,
    theme: StructuredText.HighlighterTheme
  ) {
    self.content = content
    self.languageHint = languageHint
    self.theme = theme
  }

  var body: some View {
    TextFragment(model.highlightedCode ?? AttributedString(content))
      .foregroundStyle(theme.foregroundColor)
      .task(id: {
        var hasher = Hasher()
        hasher.combine(String(content.characters[...]))
        hasher.combine(isSyntaxHighlightingEnabled)
        hasher.combine(textEnvironment)
        return hasher.finalize()
      }()) {
        await model.process(
          content: content,
          languageHint: languageHint,
          isEnabled: isSyntaxHighlightingEnabled,
          using: theme,
          environment: textEnvironment
        )
      }
  }
}

extension HighlightedTextFragment {
  @MainActor @Observable final class Model {
    var highlightedCode: AttributedString? = nil

    func process(
      content: AttributedSubstring,
      languageHint: String?,
      isEnabled: Bool,
      using theme: StructuredText.HighlighterTheme,
      environment: TextEnvironmentValues
    ) async {
      // ハイライト無効時はクリアして終了
      guard isEnabled else {
        self.highlightedCode = nil
        return
      }

      let code = String(content.characters[...])
      var tokens = [CodeToken(content: code, type: .plain)]

      if let tokenizer = CodeTokenizer.shared, let languageHint {
        tokens = await tokenizer.tokenize(code: code, language: languageHint)
      }

      // トライアル: ここでタスクがキャンセルされていたら重いハイライト処理をスキップ
      if Task.isCancelled { return }

      // --- ハイライト処理 ---
      var attributes = AttributeContainer()
      attributes.presentationIntent = content.presentationIntent
      ForegroundColorProperty(theme.foregroundColor)
        .apply(in: &attributes, environment: environment)

      var result = AttributedString()

      for token in tokens {
        var tokenContent = AttributedString(token.content)
        var tokenAttributes = attributes

        if let tokenProperties = theme.tokenProperties[token.type] {
          tokenProperties.apply(in: &tokenAttributes, environment: environment)
        }

        tokenContent.mergeAttributes(tokenAttributes)
        result.append(tokenContent)
      }

      if !Task.isCancelled {
        self.highlightedCode = result
      }
    }
  }
}
