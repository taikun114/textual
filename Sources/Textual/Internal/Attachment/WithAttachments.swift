import SwiftUI

// MARK: - Overview
//
// `WithAttachments` resolves attachment references in an `AttributedString`.
//
// Markup parsing keeps some items as URL attributes:
// - `run.imageURL` for images
// - `run.textual.emojiURL` for custom emoji references emitted by pattern expansion
//
// This view asynchronously loads those URLs using the environment-provided attachment loaders and
// writes the resolved attachments back into the attributed string as `Textual.Attachment`
// attributes. The rest of the rendering pipeline treats attachment runs like any other span.

struct WithAttachments<Content: View>: View {
  @Environment(\.imageAttachmentLoader) private var imageAttachmentLoader
  @Environment(\.emojiAttachmentLoader) private var emojiAttachmentLoader
  @Environment(\.colorEnvironment) private var colorEnvironment

  @State private var resolvedAttributedString: AttributedString?

  private let attributedString: AttributedString
  private let content: (AttributedString) -> Content

  init(
    _ attributedString: AttributedString,
    @ViewBuilder content: @escaping (AttributedString) -> Content
  ) {
    self.attributedString = attributedString
    self.content = content
  }

  var body: some View {
    content(resolvedAttributedString ?? attributedString)
      .task(id: String(attributedString.characters[...]).hashValue) {
        resolvedAttributedString = await resolveAttachments(
          in: attributedString,
          imageAttachmentLoader: imageAttachmentLoader,
          emojiAttachmentLoader: emojiAttachmentLoader,
          environment: colorEnvironment
        )
      }
  }

  private func resolveAttachments(
    in attributedString: AttributedString,
    imageAttachmentLoader: any AttachmentLoader,
    emojiAttachmentLoader: any AttachmentLoader,
    environment: ColorEnvironmentValues
  ) async -> AttributedString {
    guard attributedString.containsValues(for: [\.imageURL, \.textual.emojiURL]) else {
      return attributedString
    }

    var attachments: [AnyAttachment] = []
    var ranges: [Range<AttributedString.Index>] = []

    await withTaskGroup(
      of: (AnyAttachment?, Range<AttributedString.Index>).self
    ) { group in
      for run in attributedString.runs {
        if let imageURL = run.imageURL {
          group.addTask {
            let attachment = try? await imageAttachmentLoader.attachment(
              for: imageURL,
              text: String(attributedString[run.range].characters[...]),
              environment: environment
            )
            return (attachment.map(AnyAttachment.init), run.range)
          }
        } else if let emojiURL = run.textual.emojiURL {
          group.addTask {
            let attachment = try? await emojiAttachmentLoader.attachment(
              for: emojiURL,
              text: String(attributedString[run.range].characters[...]),
              environment: environment
            )
            return (attachment.map(AnyAttachment.init), run.range)
          }
        }
      }

      for await (attachment, range) in group {
        guard let attachment else { continue }

        attachments.append(attachment)
        ranges.append(range)
      }
    }

    var result = attributedString
    for (range, attachment) in zip(ranges, attachments) {
      result[range].textual.attachment = attachment
    }
    return result
  }
}
