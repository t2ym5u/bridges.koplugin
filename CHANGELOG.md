# Changelog

All notable changes to this project will be documented in this file.

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
