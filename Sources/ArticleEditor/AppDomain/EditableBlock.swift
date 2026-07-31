import Foundation
import GeneratorCore

public struct EditableBlock: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var block: ContentBlock

    public init(id: UUID, block: ContentBlock) {
        self.id = id
        self.block = block
    }
}
