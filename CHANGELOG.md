# Changelog

All notable changes to this project will be documented in this file.

## [1.5.1] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.5.0] - 2026-11-05

### Changed
- You now choose where bridges go: any two islands that see each other can
  be joined with 0, 1 or 2 bridges. Before, only the pairs of the solution
  could be tapped, and never past the solution's count, which gave the
  answer away.
- Every puzzle now has exactly one solution under the stated rules (bridges
  never cross, one connected network) and never needs trial and error. It
  is checked by a solver that reasons like a player: Easy needs only the
  island numbers, Medium also "two islands must not close themselves off"
  (two 1s are never joined), Hard needs at least two steps about the whole
  network. Levels now also differ in island count (7×7: 10 / 12 / 14).
- A finished grid wins whenever it keeps the rules.
- Hints also point out a pair with too many bridges and fix it.
- A "Generating puzzle…" bar shows if a puzzle takes a moment to build.
- Today's Daily Challenge puzzle changes once with this update.

### Fixed
- Puzzles were not reproducible: the generator reseeded itself from the
  clock, so the Daily Challenge differed from one device to the next.
- The generated solution often had crossing bridges, so almost no puzzle
  could be solved by the rules (29 to 30 out of 30 per size and level).
- Removed the fallback that could hand out a puzzle with several solutions.
- A bridge can no longer be drawn across another one ("Bridges cannot
  cross.").
- Saves from earlier versions load and keep the bridges already placed; a
  saved puzzle whose solution crosses itself still allows crossing bridges,
  so it stays winnable.

## [1.4.5] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.4.4] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.4.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.4.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- "Daily Challenge" in the menu, right after "New game": today's puzzle at
  your size and difficulty, the same grid for everyone playing it today.
  Needs game-common 1.7.0.

## [1.3.0] - 2026-10-30

### Changed
- Redesigned play screen: the board fills the room the controls leave, with a
  full-width Check/Hint/Reset bar.
- The status line reads "7×7 · Hard · Islands: 3/14" and wraps in landscape
  instead of being cut off.
- Title-bar menu: "Size: 7×7" and "Difficulty: Hard" instead of "Grid: 7×7"
  and "Diff: Hard".
- Once the puzzle is solved, the action bar shows "New game" in place of its
  buttons.

### Fixed
- Island numbers overflowed their circle on high-DPI screens (the size was
  scaled by DPI twice); each one is now the largest that fits inside the
  island.
- An applied Hint no longer wipes the saved game (game-common saved it as
  nil). When a hint fills the last cell, the status now shows the win message.

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
