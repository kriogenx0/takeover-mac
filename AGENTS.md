# AGENTS.md — Takeover

Takeover sets up a Mac from a settings file: it installs apps, applies macOS defaults, and links config files into place. It ships as a SwiftUI app and a `takeover` command-line tool that share code.

## Commands

- `make` (`make setup dev`): check Xcode, resolve SwiftPM dependencies, build Debug, and open it.
- `make test`: unit tests (`TakeoverTests` only; `TakeoverUITests` is excluded because it is slow and flaky).
- `make build`: Release build. `make install` / `make uninstall` / `make reinstall`: manage `/Applications`. `make package`: `build/Takeover.dmg`.
- `make cli` / `make install-cli`: build and install the `takeover` CLI.
- `make verify-sign`, `make reset-tcc`: signing check and TCC reset.
- `make close` / `make clean`; `make help` lists everything.

## Layout

- `Shared/`: code used by both the app and the CLI: `Models/` (settings YAML, link items, defaults, installers), `Lib/` (installer engines, linker, system operations, permissions), `Data/`, and config/path helpers.
- `Takeover/`: the SwiftUI app (`Views/`, `Account/`, `Profile/`, `Net/`).
- `TakeoverCLI/`: the terminal UI and command-line entry point.
- `TakeoverTests/`, `TakeoverUITests/`: XCTest suites.
- `design/`: design assets.

## Conventions

- Put logic in `Shared/` when both the app and the CLI need it, and keep it free of SwiftUI.
- The project uses synchronized folders, so new files in existing folders are picked up automatically. Check target membership for files in `Shared/`.
- Run shell commands through `SystemOps.run` / `SystemOps.require` rather than spawning processes directly. Linking replaces files at the destination, so be careful with any change to `Linker`.

## Design principles

Follow the [design principles](docs/rules/design-principles.md) for any UI work.

## After changing code

1. `make test`
2. `make dev`

Commit messages are one short, imperative line, like the existing history.
