import DataStructure
import Foundation

/// Runs a `Gen` against a threaded random number generator.
///
/// A `Gen<AnyRandomNumberGenerator, Value>` is a pure, composable *description* of how to produce a value — `Stateful` over an
/// RNG, so nothing about it is random until something threads a generator through it. This is the one
/// place that owns that generator's mutable state, which is why it lives at the boundary, below
/// `World`: everywhere above, identity is a plain thunk that happens to be honest about being a
/// side-effect.
///
/// Seeded, it is reproducible — the same seed replays the same sequence of identities, on any
/// platform, which is what makes a test that creates projects deterministic.
///
/// `@unchecked Sendable` justification: the RNG is `Sendable` but mutable, and every read-modify-write
/// of it goes through `lock`. Nothing else touches `rng`, and no reference to it escapes.
final class GenRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var rng: AnyRandomNumberGenerator

    /// - Parameter seed: `nil` uses system randomness; any value replays deterministically.
    init(seed: UInt64?) {
        rng = seed.map { AnyRandomNumberGenerator(SplitMix64(seed: $0)) }
            ?? AnyRandomNumberGenerator(SystemRandomNumberGenerator())
    }

    /// Advances the generator once and returns what `gen` describes.
    func callAsFunction<Value>(_ gen: Gen<AnyRandomNumberGenerator, Value>) -> Value {
        lock.withLock { gen(&rng) }
    }
}
