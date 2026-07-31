import CoreFP
import CoreFPOperators
import DataStructure
import DataStructureOperators
import Foundation

let fontFileNames = ["JetBrainsMono-Regular.ttf", "JetBrainsMono-Bold.ttf", "JetBrainsMono-Italic.ttf", "NOTICE.txt"]

/// URLs of the bundled JetBrains Mono `.ttf` files (Regular/Bold/Italic) — the exact
/// font the generated site embeds via `@font-face`. Callers register these at runtime
/// (e.g. `CTFontManagerRegisterFontsForURL`) to reference "JetBrains Mono" by name.
public func jetBrainsMonoFontURLs() -> [URL] {
    ["JetBrainsMono-Regular.ttf", "JetBrainsMono-Bold.ttf", "JetBrainsMono-Italic.ttf"].compactMap { fileName in
        let resourceName = (fileName as NSString).deletingPathExtension
        let resourceExtension = (fileName as NSString).pathExtension
        return Bundle.module.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Fonts")
    }
}

public func writeFonts(into directory: String) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world in
        world.createDirectory(directory) >>- {
            fontFileNames.reduce(Result<Void, GeneratorError>.success(())) { result, fileName in
                result >>- { copyFont(fileName, into: directory, using: world) }
            }
        }
    }
}

func copyFont(_ fileName: String, into directory: String, using world: World) -> Result<Void, GeneratorError> {
    let resourceName = (fileName as NSString).deletingPathExtension
    let resourceExtension = (fileName as NSString).pathExtension
    guard let sourceURL = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Fonts") else {
        return .failure(.fileCopyFailed(from: fileName, to: "\(directory)/\(fileName)", reason: "font resource not found in bundle"))
    }
    return world.copyFile(sourceURL.path, "\(directory)/\(fileName)")
}
