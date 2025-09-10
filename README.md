# AL Build Tools (overlay bootstrap)

A minimal, cross-platform build toolkit for Microsoft AL projects with a dead-simple bootstrap. It is designed to be dropped into an existing git repo and updated by running the same single command again.

Install and update are the same: the bootstrap copies everything from this repo’s `overlay/` folder into your project. Because you’re in git, you review and commit changes as you like.

## Quick Start

Linux/macOS
```
sh -c 'URL=https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh; TMP=$(mktemp); (command -v curl >/dev/null && curl -fsSL "$URL" -o "$TMP") || (command -v wget >/dev/null && wget -qO "$TMP" "$URL") || { echo "Download failed: need curl or wget" >&2; exit 1; }; bash "$TMP" -- --dest .; RC=$?; rm -f "$TMP"; exit $RC'
```

Windows (PowerShell 7+)
```
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
```

Re-run the same command any time to update — it simply re-copies `overlay/*` over your working tree.

---

## What This Repo Provides

- `overlay/` — the files that are copied into your project:
  - `Makefile` — thin dispatcher to platform scripts.
  - `scripts/make/linux/*` — build, clean, show-config, show-analyzers and helpers.
  - `scripts/make/windows/*` — PowerShell equivalents (PowerShell 7+).
  - `.gitattributes` — recommended line-ending normalization.
  - `AGENTS.md` — contributor/agent guidance (optional to keep).
- `bootstrap/` — the self-contained installers used by the one-liners above:
  - `install.sh` (bash)
  - `install.ps1` (PowerShell 7+)

## Why “overlay”?

Only the contents of `overlay/` are ever copied to your project. That keeps the bootstrap stable even if other files are added to this repository in the future.

## Requirements

- Linux/macOS: `bash`, `curl`, `tar`, and either `unzip` or `python3`
- Windows: PowerShell 7+ (`Invoke-WebRequest`, `Expand-Archive` built-in)
- Destination should be a git repo (no backups are created; git handles history and diffs)

## After Installing

- Linux
  - Build: `bash scripts/make/linux/build.sh`
  - Clean: `bash scripts/make/linux/clean.sh`
  - Show config: `bash scripts/make/linux/show-config.sh`
  - Show analyzers: `bash scripts/make/linux/show-analyzers.sh`
- Windows (PowerShell 7+)
  - Build: `pwsh -File scripts/make/windows/build.ps1`
  - Clean: `pwsh -File scripts/make/windows/clean.ps1`
  - Show config: `pwsh -File scripts/make/windows/show-config.ps1`
  - Show analyzers: `pwsh -File scripts/make/windows/show-analyzers.ps1`
- Make (optional)
  - If `make` is available: `make build`, `make clean`, etc., will dispatch to the platform scripts.

## Options (if you need them)

Both installers accept overrides. Defaults shown in parentheses.

- URL/Url (`https://github.com/FBakkensen/al-build-tools`)
- REF/Ref (`main`)
- DEST/Dest (`.`)
- SOURCE/Source (`overlay`)

Examples
- Linux/macOS (pin a tag):
  ```
  curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | bash -s -- --ref v1.2.3 --dest .
  ```
- Windows (pin a tag):
  ```
  iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Ref v1.2.3 -Dest .
  ```
- Windows (use a fork):
  ```
  iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Url 'https://github.com/yourorg/al-build-tools' -Ref main -Dest .
  ```

## How It Works

1. Downloads a ZIP of this repo at the specified ref (default `main`).
2. Copies `overlay/*` into your destination directory, overwriting existing files.
3. No state files and no backups — use git to review and commit changes.

## Troubleshooting

- “Running scripts is disabled” on Windows: start PowerShell as Administrator and run:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or use `-ExecutionPolicy Bypass` for one-off runs.
- Linux/macOS: ensure `curl` and `tar` are installed and available in `PATH`.

## Contributing

Please keep Linux and Windows behavior in parity. When adding new tasks, update both `overlay/scripts/make/linux` and `overlay/scripts/make/windows`, and keep the Makefile thin.
