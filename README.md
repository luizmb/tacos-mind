# Taco's Mind

The `Meow` static-site CLI (+ `GeneratorCore` library) and the **Taco's Mind** Article
Editor SwiftUI app (macOS/iOS) for [ios.lu](https://ios.lu) — a functional-programming
article series and videocast. Split out of
[luizmb/ios.lu](https://github.com/luizmb/ios.lu), which now holds only the article
content (`Articles/*.json`).

## What's here

- **`GeneratorCore`** — the content model, HTML/MathML rendering, Swift syntax highlighting
  (via [swift-syntax](https://github.com/swiftlang/swift-syntax)), stylesheet, and a portable
  `World` (plain `FileManager` calls, no platform-specific APIs — builds and runs on Linux).
- **`Meow`** — the CLI executable. Reads `Articles/*.json` from its current working
  directory and writes the generated site to `dist/`.
- **Taco's Mind** — a native SwiftUI app (macOS + iOS) for writing and editing the JSON
  articles directly: metadata, blocks, tags, an on-device AI assistant (voice or text) for
  brainstorming, GitHub sync (pull/commit/PR against `ios.lu`), and Cmd+R/Cmd+B to
  generate-and-preview or generate-the-whole-site in-process (no shell-out, works on iOS too).

## Development

```bash
swift build 2>&1 | xcsift   # xcsift is local-only — never pipe through it in CI
swift test 2>&1 | xcsift
```

Taco's Mind (the app) is built/run via `TacosMind.xcodeproj` (schemes `TacosMind-macOS` /
`TacosMind-iOS`).

To generate a site locally, run `Meow` with an `ios.lu` checkout (or any directory
containing `Articles/*.json`) as the working directory:

```bash
cd /path/to/ios.lu
swift run --package-path /path/to/tacos-mind Meow            # drafts included
swift run --package-path /path/to/tacos-mind Meow --publish  # drafts excluded
```

## Releases

Versioning lives in git refs, not a file — mirrors the process used by
[luizmb/FP](https://github.com/luizmb/FP):

1. **Create RC** (`workflow_dispatch`, `create-rc.yml`) — bumps `MARKETING_VERSION`/
   `CURRENT_PROJECT_VERSION` in `TacosMind.xcodeproj`, commits to `main`, creates and
   pushes a `release/X.Y.Z` branch.
2. That branch push triggers the RC build (`release.yml`): both Xcode schemes + `swift test`.
3. **Promote RC** (`workflow_dispatch`, `promote-rc.yml`) — once the RC build is green, tags
   the release branch `vX.Y.Z` and pushes the tag.
4. The tag push triggers the promote phase (`release.yml`): a GitHub Release is created with
   a changelog, and two `Meow` binaries are attached as release assets — `Meow-linux-x86_64`
   (what `ios.lu`'s own publish workflow downloads to build the site) and
   `Meow-macos-universal` (arm64 + x86_64, for running `Meow` locally on either kind of Mac
   without building from source).

## Layout

- `Sources/GeneratorCore/` — content model, rendering, `World`
- `Sources/Meow/` — CLI entry point (`main.swift`)
- `Sources/App/` — Taco's Mind's `@main` entry point
- `Sources/ArticleEditor/` — the app's SwiftRex features (`AppDomain`, `FileWatching`,
  `ArticleListFeature`, `ArticleEditorFeature`, `AIChatFeature`, `GitHubSyncFeature`, `AppCore`)
- `Tests/` — one test target per `Sources/` target above
- `TacosMind.xcodeproj/` — the Xcode project wrapping the SPM package for the app
