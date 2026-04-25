import SwiftUI

extension EnvironmentValues {
  @Entry public var listItemSpacing: FontScaled<StructuredText.BlockSpacing> = .fontScaled(top: 0.25)
  @Entry public var listSpacing: FontScaled<StructuredText.BlockSpacing> = .fontScaled(top: 0, bottom: 0)
  @Entry var resolvedListItemSpacing: StructuredText.BlockSpacing = .init()
  @Entry var listItemSpacingEnabled: Bool = false
}
