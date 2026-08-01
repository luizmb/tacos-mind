import Foundation

public enum GeneratorError: Error, Sendable, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case directoryRemovalFailed(path: String, reason: String)
    case fileWriteFailed(path: String, reason: String)
    case fileCopyFailed(from: String, to: String, reason: String)
}

public struct World: Sendable {
    public var currentDate: @Sendable () -> Date
    public var createDirectory: @Sendable (String) -> Result<Void, GeneratorError>
    public var removeDirectory: @Sendable (String) -> Result<Void, GeneratorError>
    public var writeFile: @Sendable (String, String) -> Result<Void, GeneratorError>
    public var copyFile: @Sendable (String, String) -> Result<Void, GeneratorError>

    public init(
        currentDate: @escaping @Sendable () -> Date,
        createDirectory: @escaping @Sendable (String) -> Result<Void, GeneratorError>,
        removeDirectory: @escaping @Sendable (String) -> Result<Void, GeneratorError>,
        writeFile: @escaping @Sendable (String, String) -> Result<Void, GeneratorError>,
        copyFile: @escaping @Sendable (String, String) -> Result<Void, GeneratorError>
    ) {
        self.currentDate = currentDate
        self.createDirectory = createDirectory
        self.removeDirectory = removeDirectory
        self.writeFile = writeFile
        self.copyFile = copyFile
    }
}
