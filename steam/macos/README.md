# macOS Steam Scripts

This directory contains macOS shell scripts for finding Steam-related game files and removing Steam application data.

## Scripts

- `macos_find_steam_game_files.sh`: searches `~/Library` for files and folders matching a game name.
- `macos_steam_app_cleanup.sh`: closes Steam, removes the Steam app, deletes common Steam support files, caches, logs, preferences, and then lists any remaining Steam-related files in `~/Library`.

## Make Scripts Executable

Before running either script, make it executable with `chmod`:

```sh
chmod +x macos_find_steam_game_files.sh
chmod +x macos_steam_app_cleanup.sh
```

## Usage

Find files for a game:

```sh
./macos_find_steam_game_files.sh "Game Name"
```

Clean up Steam from macOS:

```sh
./macos_steam_app_cleanup.sh
```

The cleanup script removes application and user support files. Review it before running, and expect the application removal step to require administrator approval because it uses `sudo`.
