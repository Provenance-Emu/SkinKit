import Foundation
import SkinKit2Bake

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 2 else {
        FileHandle.standardError.write(Data("usage: skinkit-bake <skin.json> <output-directory>\n".utf8))
        exit(2)
    }
    let source = URL(fileURLWithPath: args[0])
    let output = URL(fileURLWithPath: args[1], isDirectory: true)
    let bundles = try Skin2Baker.bake(sourceURL: source)
    let destinations = try Skin2Baker.write(bundles, to: output)
    for (bundle, destination) in zip(bundles, destinations) {
        print(destination.path)
        for warning in bundle.warnings { FileHandle.standardError.write(Data((warning + "\n").utf8)) }
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("skinkit-bake: \(error)\n".utf8))
    exit(1)
}
