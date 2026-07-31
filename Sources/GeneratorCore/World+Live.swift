import Foundation
import Hourglass

extension World {
    public static let live = World(
        currentDate: { WallClock().now.date },
        createDirectory: { path in
            Result { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
                .mapError { GeneratorError.directoryCreationFailed(path: path, reason: $0.localizedDescription) }
        },
        removeDirectory: { path in
            Result {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(atPath: path)
                }
            }
            .mapError { GeneratorError.directoryRemovalFailed(path: path, reason: $0.localizedDescription) }
        },
        writeFile: { path, contents in
            Result { try contents.write(toFile: path, atomically: true, encoding: .utf8) }
                .mapError { GeneratorError.fileWriteFailed(path: path, reason: $0.localizedDescription) }
        },
        copyFile: { source, destination in
            Result {
                if FileManager.default.fileExists(atPath: destination) {
                    try FileManager.default.removeItem(atPath: destination)
                }
                try FileManager.default.copyItem(atPath: source, toPath: destination)
            }
            .mapError { GeneratorError.fileCopyFailed(from: source, to: destination, reason: $0.localizedDescription) }
        }
    )
}
