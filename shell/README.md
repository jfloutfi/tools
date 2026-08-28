# Shell utilities

Small Zsh utilities for inspecting and working with the terminal.

## Contents

- `check-terminal-tools.sh` — Reports whether a curated set of terminal tools is installed, along with each tool's version, executable path, and detected installation source. It supports macOS (including Homebrew) and common Linux package ecosystems.
- `colors.sh` — Prints a preview of all 256 terminal colors.

## Usage

Run the terminal-tools report with Zsh:

```sh
./check-terminal-tools.sh
```

Set `NO_COLOR=1` to disable colors, or `FORCE_COLOR=1` to enable them when output is not attached to a terminal:

```sh
NO_COLOR=1 ./check-terminal-tools.sh
```

Run the color preview with:

```sh
./colors.sh
```
