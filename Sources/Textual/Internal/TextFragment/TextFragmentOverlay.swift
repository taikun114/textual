import SwiftUI

// MARK: - Overview
//
// `TextFragmentOverlay` は `AttachmentOverlay` と `TextLinkInteraction` を統合した
// フラグメントレベルのオーバーレイ。
//
// 従来は `AttachmentOverlay` と `TextLinkInteraction` がそれぞれ独立して
// `overlayPreferenceValue(Text.LayoutKey.self)` + `GeometryReader` を持っていたが、
// これらは同じプリファレンスキーを参照しており、統合することで `GeometryReader` の
// 評価回数を半減させ、スクロール時のCPU使用率を大幅に低減する。

struct TextFragmentOverlay: ViewModifier {
  @Environment(\.openURL) private var openURL
  private let attachments: Set<AnyAttachment>

  init(attachments: Set<AnyAttachment>) {
    self.attachments = attachments
  }

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_LINKS
      content
        .overlayPreferenceValue(Text.LayoutKey.self) { value in
          if let anchoredLayout = value.first {
            GeometryReader { geometry in
              let origin = geometry[anchoredLayout.origin]
              let layout = anchoredLayout.layout

              // 添付ファイルが存在する場合のみ AttachmentView を描画
              if !attachments.isEmpty {
                AttachmentView(
                  attachments: attachments,
                  origin: origin,
                  layout: layout
                )
              }

              // リンクタップジェスチャー
              Color.clear
                .contentShape(.rect)
                .gesture(
                  tap(origin: origin, layout: layout)
                )
            }
          }
        }
    #else
      if attachments.isEmpty {
        content
      } else {
        content
          .overlayPreferenceValue(Text.LayoutKey.self) { value in
            if let anchoredLayout = value.first {
              GeometryReader { geometry in
                AttachmentView(
                  attachments: attachments,
                  origin: geometry[anchoredLayout.origin],
                  layout: anchoredLayout.layout
                )
              }
            }
          }
      }
    #endif
  }

  #if TEXTUAL_ENABLE_LINKS
    private func tap(origin: CGPoint, layout: Text.Layout) -> some Gesture {
      SpatialTapGesture()
        .onEnded { value in
          let localPoint = CGPoint(
            x: value.location.x - origin.x,
            y: value.location.y - origin.y
          )
          let runs = layout.flatMap(\.self)
          let run = runs.first { run in
            run.typographicBounds.rect.contains(localPoint)
          }
          guard let url = run?.url else {
            return
          }
          openURL(url)
        }
    }
  #endif
}
