import SwiftUI

/// A view that displays rich, structured text.
///
/// `StructuredText` renders block elements like paragraphs, headings, lists, block quotes, code
/// blocks, and tables from a markup string. The markup is parsed with a ``MarkupParser`` into an
/// `AttributedString` that Textual can lay out and display.
///
/// The simplest way to create a `StructuredText` view is to pass Markdown:
///
/// ```swift
/// let markdown = """
/// ## Getting Started
///
/// Before making changes, check a few things:
///
/// - Skim recent commits
/// - Run the tests
/// - Make your changes
///
/// Leave a note if something needs attention later.
/// """
///
/// var body: some View {
///   StructuredText(markdown: markdown)
/// }
/// ```
///
/// ### Customizing Text Appearance
///
/// `StructuredText` supports standard SwiftUI text modifiers like `.font()`, `.foregroundStyle()`,
/// and `.multilineTextAlignment()`. Note that `.lineLimit()` is explicitly disabled to prevent
/// per-block truncation, which would break the document layout.
///
/// ```swift
/// StructuredText(markdown: "## Hello\n\nThis is a paragraph.")
///   .font(.callout)
///   .foregroundStyle(.blue)
///   .multilineTextAlignment(.center)
/// ```
///
/// ### Styling Structured Text
///
/// You can apply a full style preset using the ``TextualNamespace/structuredTextStyle(_:)`` modifier.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .textual.structuredTextStyle(.gitHub)
/// ```
///
/// For more control, you can customize individual block and inline styles. Inline styles
/// apply to spans like emphasis and links. Block styles apply to structural elements:
///
/// - ``TextualNamespace/headingStyle(_:)``, ``TextualNamespace/paragraphStyle(_:)``,
///   ``TextualNamespace/blockQuoteStyle(_:)``, ``TextualNamespace/thematicBreakStyle(_:)``
/// - ``TextualNamespace/listItemStyle(_:)``, ``TextualNamespace/unorderedListMarker(_:)``,
///   ``TextualNamespace/orderedListMarker(_:)``
/// - ``TextualNamespace/codeBlockStyle(_:)``, ``TextualNamespace/highlighterTheme(_:)``
/// - ``TextualNamespace/tableStyle(_:)``, ``TextualNamespace/tableCellStyle(_:)``
///
/// Code blocks and tables may overflow horizontally. You can choose between scrolling and
/// wrapping with ``TextualNamespace/overflowMode(_:)``.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .textual.overflowMode(.wrap)
/// ```
///
/// ### Interaction
///
/// When the markup contains links, `StructuredText` uses SwiftUI’s `openURL` environment. Provide a
/// custom `OpenURLAction` to intercept them (for example, to route in-app or to scroll to anchors).
///
/// You can enable text selection with ``TextualNamespace/textSelection(_:)`` to let users select
/// text in a platform-appropriate way.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .environment(
///     \.openURL,
///     OpenURLAction { url in
///       print("Open \(url)")
///       return .handled
///     }
///   )
///   .textual.textSelection(.enabled)
/// ```
///
/// ### Images, links, and relative URLs
///
/// If your Markdown includes relative image URLs or links, provide a `baseURL`. To render images,
/// configure an attachment loader using the ``TextualNamespace/imageAttachmentLoader(_:)``
/// modifier.
///
/// ```swift
/// let baseURL = URL(string: "https://example.com/repo/")!
///
/// StructuredText(markdown: readme, baseURL: baseURL)
///   .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
/// ```
///
/// When you need to parse something other than Markdown, use ``init(_:parser:)`` with a custom
/// ``MarkupParser`` implementation.
public struct StructuredText: View {
  @State private var attributedString: AttributedString

  private let markup: String
  private let parser: any MarkupParser

  // Streaming内のブロックでは親がテキスト選択を管理するため、個別のInteractionを無効化する
  var managesOwnSelection: Bool = true

  /// Creates a structured-text view by parsing `markup` with a custom parser.
  ///
  /// Use this initializer when you want to provide your own `MarkupParser` implementation.
  public init(_ markup: String, parser: any MarkupParser) {
    self.markup = markup
    self.parser = parser
    // 初回表示時の空文字フレームによるチラつきを防ぐため、初期値を同期的にパースしてセット
    self._attributedString = State(initialValue: (try? parser.attributedString(for: markup)) ?? .init())
  }

  public var body: some View {
    WithAttachments(attributedString) {
      BlockContent(content: $0)
        .coordinateSpace(.textContainer)
        .if(managesOwnSelection) {
          $0.modifier(TextSelectionInteraction())
            .modifier(TextSelectionCoordination())
        }
        .accessibilityElement(children: .contain)
    }
    .task(id: markup) {
      // Offload parsing to a background thread and cancel existing stale tasks
      // to handle high-frequency updates (e.g., during streaming).
      let parsed = await Task.detached(priority: .userInitiated) {
        (try? parser.attributedString(for: markup)) ?? .init()
      }.value

      if !Task.isCancelled {
        self.attributedString = parsed
      }
    }
    // Disable line limit to avoid per-fragment truncation
    .lineLimit(nil)
  }
}

extension StructuredText {
  /// A version of `StructuredText` optimized for streaming content.
  ///
  /// Incremental parsing and rendering are performed by splitting the markdown into blocks.
  public struct Streaming: View {
    private let markdown: String
    private let baseURL: URL?
    private let syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension]
    private let isStreaming: Bool

    @State private var model: StreamingModel

    public init(
      markdown: String,
      baseURL: URL? = nil,
      syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
      isStreaming: Bool = false
    ) {
      self.markdown = markdown
      self.baseURL = baseURL
      self.syntaxExtensions = syntaxExtensions
      self.isStreaming = isStreaming
      self._model = State(
        initialValue: StreamingModel(
          markdown: markdown,
          baseURL: baseURL,
          syntaxExtensions: syntaxExtensions,
          isStreaming: isStreaming
        )
      )
    }

    public var body: some View {
      BlockVStack {
        ForEach(model.blocks) { block in
          BlockView(block: block)
        }
      }
      .coordinateSpace(.textContainer)
      .transaction { transaction in
        transaction.animation = nil
      }
      .modifier(TextSelectionInteraction())
      .modifier(TextSelectionCoordination())
      .task(id: markdown) {
        await model.process(
          markdown: markdown,
          baseURL: baseURL,
          syntaxExtensions: syntaxExtensions,
          isStreaming: isStreaming
        )
      }
    }

    @MainActor @Observable final class StreamingModel {
      var blocks: [BlockInfo] = []
      private var lastUpdateTime: Date = .distantPast

      init(
        markdown: String? = nil,
        baseURL: URL? = nil,
        syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
        isStreaming: Bool = false
      ) {
        if let markdown, !markdown.isEmpty {
          let parser = AttributedStringMarkdownParser(
            baseURL: baseURL,
            syntaxExtensions: syntaxExtensions
          )
          let rawBlocks = MarkdownBlockSplitter.split(markdown, isStreaming: isStreaming)
          self.blocks = rawBlocks.map { newBlock in
            let parsedAttr = (try? parser.attributedString(for: newBlock.renderMarkdown)) ?? AttributedString()
            return BlockInfo(
              markdown: newBlock.markdown,
              renderMarkdown: newBlock.renderMarkdown,
              kind: newBlock.kind,
              isUnclosedCodeBlock: newBlock.isUnclosedCodeBlock,
              attributedString: parsedAttr
            )
          }
          self.lastUpdateTime = Date()
        }
      }

      func process(
        markdown: String,
        baseURL: URL?,
        syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension],
        isStreaming: Bool
      ) async {
        let interval: TimeInterval = isStreaming ? 0.08 : 0.0 // ストリーミング中は 80ms 間隔でスロットリング

        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdateTime)
        if elapsed < interval {
          let delay = interval - elapsed
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if Task.isCancelled { return }

        let previousBlocks = self.blocks

        let updatedBlocks = await Task.detached(priority: .userInitiated) {
          let parser = AttributedStringMarkdownParser(
            baseURL: baseURL,
            syntaxExtensions: syntaxExtensions
          )
          let rawBlocks = MarkdownBlockSplitter.split(markdown, isStreaming: isStreaming)

          var processedBlocks: [BlockInfo] = []
          for (index, newBlock) in rawBlocks.enumerated() {
            if index < previousBlocks.count {
              let existing = previousBlocks[index]
              if existing.markdown == newBlock.markdown &&
                 existing.renderMarkdown == newBlock.renderMarkdown &&
                 existing.kind == newBlock.kind &&
                 existing.isUnclosedCodeBlock == newBlock.isUnclosedCodeBlock {
                // 内容に変更がない過去ブロックはパース済みの AttributedString と既存 ID をそのまま再利用（キャッシュ）
                processedBlocks.append(existing)
                continue
              }
            }

            // 新規または更新されたブロックのみバックグラウンドでパースを実行
            let parsedAttr = (try? parser.attributedString(for: newBlock.renderMarkdown)) ?? AttributedString()
            let blockId = (index < previousBlocks.count && previousBlocks[index].kind == newBlock.kind) ? previousBlocks[index].id : UUID()
            processedBlocks.append(
              BlockInfo(
                id: blockId,
                markdown: newBlock.markdown,
                renderMarkdown: newBlock.renderMarkdown,
                kind: newBlock.kind,
                isUnclosedCodeBlock: newBlock.isUnclosedCodeBlock,
                attributedString: parsedAttr
              )
            )
          }
          return processedBlocks
        }.value

        if Task.isCancelled { return }

        if self.blocks != updatedBlocks {
          self.blocks = updatedBlocks
          self.lastUpdateTime = Date()
        }
      }
    }

    // ブロック単位の描画を最適化するためのEquatableなラッパーView
    private struct BlockView: View, Equatable {
      let block: BlockInfo

      @Environment(\.listSpacing) private var listSpacing

      nonisolated static func == (lhs: BlockView, rhs: BlockView) -> Bool {
        return lhs.block.id == rhs.block.id &&
               lhs.block == rhs.block
      }

      var body: some View {
        WithAttachments(block.attributedString) {
          BlockContent(content: $0)
            .accessibilityElement(children: .contain)
        }
        .lineLimit(nil)
        .textual.blockSpacing(spacing(for: block.kind))
        .transaction { transaction in
          transaction.animation = nil
        }
      }

      private func spacing(for kind: BlockKind) -> FontScaled<BlockSpacing> {
        switch kind {
        case .list:
          return listSpacing
        case .table:
          return .fontScaled(top: 0.8, bottom: 0.8)
        case .codeBlock:
          return .fontScaled(top: 0.8, bottom: 0.8)
        case .header:
          return .fontScaled(top: 0)
        default:
          return .fontScaled(top: 0.8, bottom: 0.8)
        }
      }
    }
  }
}

extension StructuredText {
  /// Creates a structured-text view from a Markdown string.
  ///
  /// This is a convenience initializer that uses Textual’s Markdown parser. To render other
  /// markup formats, use ``init(_:parser:)`` with a custom ``MarkupParser``.
  ///
  /// - Parameters:
  ///   - markdown: The Markdown source to render.
  ///   - baseURL: A base URL used to resolve relative links and image URLs.
  ///   - syntaxExtensions: Custom syntax extensions applied after markdown parsing.
  ///
  /// Math expressions are supported when you include `.math` in `syntaxExtensions`:
  ///
  /// ```swift
  /// StructuredText(
  ///   markdown: "The area is $A = \\pi r^2$.",
  ///   syntaxExtensions: [.math]
  /// )
  /// ```
  public init(
    markdown: String,
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = []
  ) {
    self.init(
      markdown,
      parser: .markdown(
        baseURL: baseURL,
        syntaxExtensions: syntaxExtensions
      )
    )
  }
}

@available(tvOS, unavailable)
@available(watchOS, unavailable)
#Preview(traits: .fixedLayout(width: 400, height: 600)) {
  @Previewable @State var width: CGFloat = 200

  VStack {
    GroupBox {
      HStack {
        Text("Width")
        Slider(value: $width, in: 100...320)
      }
    }
    Spacer()

    StructuredText(
      markdown: """
        Morty, do you know what _“wubba lubba dub dub”_ means?

        ![Hamster in Butt World](https://rickandmortyapi.com/api/character/avatar/153.jpeg)

        I mean, why would a [Pop-Tart](https://en.wikipedia.org/wiki/Pop-Tarts) \
        want to live inside a toaster, Rick? I mean, that would be like the \
        scariest place for them to live. You know what I mean?
        """
    )
    .frame(width: width)
    .border(Color.red)
    .environment(
      \.openURL,
      OpenURLAction { url in
        print("Opening \(url)")
        return .handled
      }
    )
    .padding()
    .textual.textSelection(.enabled)

    Spacer()
  }
}

#Preview("Custom Emoji") {
  let emoji: Set<Emoji> = [
    Emoji(shortcode: "dog", url: URL(string: "https://picsum.photos/id/237/32/32")!),
    Emoji(shortcode: "cat", url: URL(string: "https://picsum.photos/id/1025/32/32")!),
  ]

  ScrollView {
    StructuredText(
      markdown: """
        # Working with Custom Emoji

        You can substitute shortcodes with inline images. For example, :dog: and :cat: render \
        as small inline attachments that flow with the surrounding text.
        """,
      syntaxExtensions: [.emoji(emoji)]
    )
    .padding()
  }
}
