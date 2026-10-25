# Contributing to Storage Sweep

Thanks for helping! Storage Sweep is a small, friendly project, and every contribution counts: code, bug reports, ideas, docs and translations.

## Ways to help

- **Report a bug:** [open a bug report](../../issues/new?template=bug_report.yml).
- **Suggest a cache or folder to clean:** [suggest a location](../../issues/new?template=new_location.yml). Tell us the path, what creates it and whether it's rebuilt automatically.
- **Suggest a feature:** [open a feature request](../../issues/new?template=feature_request.yml).
- **Pick up an issue:** look for [`good first issue`](../../labels/good%20first%20issue) or [`help wanted`](../../labels/help%20wanted). Comment on it so others know you're on it.

## Set up

1. Fork the repo and clone your fork.
2. You need macOS 13+ and Xcode 15+.
3. Build and run:

   ```bash
   ./build.sh && open "dist/Storage Sweep.app"
   ```

   Or open the folder in Xcode and press **Run**. `swift build` works too for a quick compile check.

## Adding a new cleanup location (good first contribution)

Most new locations are a single line in `knownLocations` inside `Sources/StorageSweep/DiskScanner.swift`:

```swift
KnownLocation(path: ".bun/install/cache", name: "Bun cache",
              note: "Re-downloaded by bun install", safety: .safe, group: "Developer caches"),
```

- `path` is relative to the home folder.
- Use `.safe` **only** if the tool recreates the folder automatically with no data loss. Otherwise use `.review`.
- Mention in your pull request where you confirmed the folder is safe to remove (official docs are best).

For project-level folders (like `node_modules`), see `dependencyNote(_:)` in the same file. Each folder must be identified by a marker file in the project (for example `Podfile` next to `Pods`), so we never flag an unrelated folder that happens to have the same name.

## Safety rules (please read)

Storage Sweep deletes files, so safety matters more than features.

- Never remove anything without the user's confirmation, and always move items to the Trash rather than deleting them permanently.
- Don't weaken `SafetyGuard` in `Safety.swift` without discussing it in an issue first.
- Never mark something `.safe` if removing it can lose user data (documents, settings, databases, simulator data, emulator data, backups).
- No network requests, analytics or telemetry.

## Code style

- Swift 5.9, SwiftUI, macOS 13 APIs. Don't use newer APIs unless they're behind `#available`.
- Keep scanning work off the main thread (see how `AppState.start` does it).
- Small, focused pull requests are easier to review than big ones.
- Clear names over clever code. Comments explain *why*, not *what*.

## Pull requests

1. Create a branch: `git checkout -b feature/bun-cache`.
2. Make your change and check that `swift build` passes and the app runs.
3. Add a line to the **Unreleased** section of `CHANGELOG.md`.
4. Open a pull request and fill in the template. Include a screenshot for UI changes.

CI builds every pull request on macOS. A maintainer will review it, usually within a few days.

## Commit messages

Use a short summary in the present tense, for example:

```
Add Bun install cache to Caches & Junk
Fix size bar overflowing in Space Explorer
```

## Code of Conduct

By taking part you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).
