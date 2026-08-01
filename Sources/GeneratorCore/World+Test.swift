import Foundation

extension World {
    public static func test(
        currentDate: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
        createDirectory: @escaping @Sendable (String) -> Result<Void, GeneratorError> = { _ in .success(()) },
        removeDirectory: @escaping @Sendable (String) -> Result<Void, GeneratorError> = { _ in .success(()) },
        writeFile: @escaping @Sendable (String, String) -> Result<Void, GeneratorError> = { _, _ in .success(()) },
        copyFile: @escaping @Sendable (String, String) -> Result<Void, GeneratorError> = { _, _ in .success(()) }
    ) -> World {
        World(
            currentDate: currentDate,
            createDirectory: createDirectory,
            removeDirectory: removeDirectory,
            writeFile: writeFile,
            copyFile: copyFile
        )
    }
}
