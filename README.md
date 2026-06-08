# Bridges

> **Status: stub — not yet implemented**

## Description

Connect islands (circles with numbers) with horizontal or vertical bridges so each island has exactly the indicated degree.

## Files to create

- `board.lua` — game logic, puzzle generator, serialize/load
- `board_widget.lua` — grid rendering and tap gestures
- `screen.lua` — full-screen layout (buttons + board)
- `main.lua` — PluginBase entry point

## Notes

Grid-based logic puzzle — use GridWidgetBase from game-common.
