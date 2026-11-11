import Foundation
import SkinKit2Bake
import SkinKit2Core

func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    let overlapPolicy: Skin2Validator.HitOverlapPolicy
    if args.first == "--allow-hit-overlaps" {
        args.removeFirst()
        overlapPolicy = .warn
    } else {
        overlapPolicy = .reject
    }
    guard args.count == 2 else {
        FileHandle.standardError.write(Data("usage: skinkit-bake [--allow-hit-overlaps] <skin.json> <output-directory>\n".utf8))
        exit(2)
    }
    let source = URL(fileURLWithPath: args[0])
    let output = URL(fileURLWithPath: args[1], isDirectory: true)
    let bundles = try Skin2Baker.bake(sourceURL: source, hitOverlapPolicy: overlapPolicy)
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
