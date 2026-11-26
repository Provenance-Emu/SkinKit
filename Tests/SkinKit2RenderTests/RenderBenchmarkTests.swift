import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

/// Main-thread cost of one redraw while a control is held (issue 162). Not an assertion on time: it prints the
/// numbers. Run it optimised, on its own:
///
///     SKIN2_BENCH=1 xcrun swift test -c release -Xswiftc -enable-testing --filter RenderBenchmark
@Suite("Format 2.0 redraw benchmark", .serialized)
struct RenderBenchmarkTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["SKIN2_BENCH"] == "1" }

    struct Scenario {
        var name: String
        var resolution: Skin2Resolution
        var options: Skin2RenderOptions
        var frames: [[String: Skin2ControlState]]
    }

    static func scenarios() throws -> [Scenario] {
        let heavy = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cube = try CacheFixtures.fixture("gamecube-icube")
        let cubeStick = cube.controls.first { $0.node.kind == .thumbstick }?.id
        var out = [
            Scenario(name: "shadows+blur skin, stick held and moved", resolution: heavy, options: CacheFixtures.options(),
                     frames: CacheFixtures.stickSweep("stick", count: 24)),
            Scenario(name: "shadows+blur skin, button press ease", resolution: heavy, options: CacheFixtures.options(),
                     frames: CacheFixtures.pressEase("a")),
        ]
        if let cubeStick {
            out.append(Scenario(name: "gamecube-icube fixture, stick held and moved", resolution: cube,
                                options: CacheFixtures.options("gamecube-icube"), frames: CacheFixtures.stickSweep(cubeStick, count: 24)))
        }
        return out
    }

    /// Milliseconds per redraw: the median over every frame of `rounds` passes.
    static func measure(_ scenario: Scenario, rounds: Int = 5, scale: CGFloat = 3,
                        draw: (CGContext, Skin2RenderOptions) -> Void) -> Double {
        let ctx = CacheFixtures.canvas(scenario.resolution, scale: scale)
        var samples: [Double] = []
        for _ in 0..<rounds {
            for states in scenario.frames {
                var options = scenario.options
                options.states = states
                let start = DispatchTime.now().uptimeNanoseconds
                CacheFixtures.clear(ctx)
                draw(ctx, options)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    @Test("Redraw time while a control is held", .enabled(if: enabled))
    func heldControl() throws {
        let only = ProcessInfo.processInfo.environment["SKIN2_BENCH_ONLY"].flatMap(Int.init)
        for (index, scenario) in try Self.scenarios().enumerated() where only == nil || only == index {
            let size = scenario.resolution.environment.size
            let direct = Self.measure(scenario, rounds: 1) { ctx, options in Skin2Renderer.draw(scenario.resolution, in: ctx, options: options) }
            let cache = Skin2RenderCache()
            let warm = CacheFixtures.canvas(scenario.resolution, scale: 3)
            let start = DispatchTime.now().uptimeNanoseconds
            cache.draw(scenario.resolution, in: warm, options: scenario.options)
            let build = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            let rounds = Int(ProcessInfo.processInfo.environment["SKIN2_BENCH_ROUNDS"] ?? "") ?? 5
            let cached = Self.measure(scenario, rounds: rounds) { ctx, options in cache.draw(scenario.resolution, in: ctx, options: options) }
            let rest = Self.measure(scenario) { ctx, _ in cache.draw(scenario.resolution, in: ctx, options: scenario.options) }
            let stats = cache.statistics
            print(String(format: "BENCH %@ (%.0f×%.0f pt @3x, %d nodes): full tree %.2f ms/redraw; cached %.2f ms/redraw (%.0f× less), "
                         + "at rest %.2f ms, one-time image %.1f ms, %.1f MB; %d trees painted, %.1f nodes per partial redraw",
                         scenario.name, size.width, size.height, scenario.resolution.nodes.count, direct, cached, direct / cached, rest, build,
                         Double(cache.byteCount) / 1_048_576, stats.fullTreeRenders, Double(stats.partialNodes) / Double(max(1, stats.partialDraws))))
        }
    }
}
