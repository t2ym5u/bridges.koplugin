# Changelog

All notable changes to this project will be documented in this file.

## [1.2.2] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.2.1] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button, working in a bridge between two islands rather than in cells. Two taps: the first names the two islands a bridge is missing between, the second builds it. A wrong bridge cannot exist here -- tapping is clamped to the solution's count -- so it only ever reports what is missing.

## [1.1.8] - 2026-07-29

### Fixed
- Generated puzzles had no uniqueness verification — the fixed island
  graph shipped as soon as one valid bridge-count assignment was found,
  with no check that it was the only one consistent with the shown
  island targets. The underlying construction was already close to
  uniquely solvable (roughly 93-100% across sizes/difficulties), but the
  remaining cases were real ambiguity. Added a backtracking uniqueness
  solver and reworked generation to retry the layout until one is proven
  unique. Regression testing now measures 100% unique across every size
  and difficulty tested.
