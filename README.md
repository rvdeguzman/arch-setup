# Personal Arch setup

Omarchy-style convenience, personal package choices. **Plain Bash + Make, plain copied configs.** No chezmoi, Nix, custom distro, or custom ISO.

This is an initial, reviewed bootstrap repository for **fresh Arch installations**. It is not an in-place Omarchy remover, and it has not yet been validated by reinstalling a laptop. Mutating targets refuse Omarchy and unaudited hardware profiles.

## Selected defaults

- Ext4, no encryption, Limine. Snapshots are not required or configured.
- Hyprland, Ly, Waybar, Fuzzel; Ghostty opens as the default workspace.
- Wi-Fi: Impala + iwd + systemd-networkd + systemd-resolved; no NetworkManager.
- Bluetooth: BlueZ + bluetui. Tailscale is a system service.
- Sioyek, Doom Emacs, Neovim, pi, Ghostty, Herdr, tmux, Typst.
- Zsh + Oh My Zsh + Starship and the familiar CLI utilities.
- Python via uv, C/raylib, TypeScript/Node included by default. Go optional.
- Brave and 1Password. No credential import or authentication is automated.
- No Docker/Colima, TeX Live, default Go toolchain, or automatic package removal. Building Paru may install Rust build dependencies.

## Start here

Read [the installation runbook](docs/install.md) before running mutating targets.

```sh
make plan HOST=minibook       # read-only package/service overview
make diff HOST=minibook       # preview selected file differences
make bootstrap HOST=minibook  # plan only; NEVER installs automatically
make test
make lint
```

Scripts require Bash 4.3+ (provided by Arch) and standard Arch tools, not Python. The `python` package is part of the desired machine/tooling environment, not an installer dependency.

### Explicit installation stages

Run as the normal user. Each mutating stage asks for a typed confirmation; there is no unattended `--yes`. System stages use sudo in your own terminal.

```sh
make packages HOST=minibook    # pacman -Syu --needed; official packages only
make paru HOST=minibook        # fetch/review/build helper once; preserve existing Paru
make aur HOST=minibook         # installed Paru handles AUR review/build/install
make sources HOST=minibook     # clone missing config/OMZ repos, never pull/reset
make diff HOST=minibook
make apply-user HOST=minibook  # back up then copy selected user files
make apply-system HOST=minibook
```

Install Paru once with `make paru` before `make aur`. The AUR target passes the selected lists to `paru -S --needed --review --aur`, with interactive build-script review. `make aur-plan` previews the selection; `PACKAGE=name` optionally selects one declared package. Official packages still use pacman. External installers, boot checks and service activation are separate steps documented in the runbook. `make services` enables services for the next boot, not `--now`; it refuses competing network/display managers.

### Package lists are the source of intent

| File | Purpose |
|---|---|
| `packages/base.txt` | OS, connectivity, audio, standard system services |
| `packages/desktop.txt` | Hyprland/Ly, bar/launcher, portals, fonts |
| `packages/workspace.txt` | Personal applications, CLI tools, uv/Typst, editor prerequisites |
| `packages/development.txt` | C/raylib and TypeScript tooling; enabled by default |
| `packages/aur.txt` | Stable Sioyek AppImage, Brave, 1Password, Hunk; separate review/build |
| `hosts/minibook/packages.txt` | Intel media/firmware and power components |
| `hosts/minibook/aur.txt` | MiniBook tablet-mode support |
| `packages/optional-go.txt` | `EXTRA=go` |
| `packages/optional-boot-aur.txt` | `BOOT_HOOK=1`, only after choosing kernel-update integration |

`DEV=0` skips the optional development list, not essential editor/AUR build prerequisites or Node used by pi. Arch package names differ from Brew: `github-cli` provides `gh`, `nodejs-lts-krypton` supplies Node 24 LTS, and `emacs-wayland` is the Linux Emacs build. Sioyek's currently available stable AUR option is `sioyek-appimage`; `sioyek-git` is deliberately not the default. Hunk is available separately in AUR.

These lists do **not** pin rolling Arch versions or record every dependency. They never automatically delete packages that are not listed.

## Configs and safety

`configs/files.tsv` declares exact files to copy. Files stay ordinary and editable. Manually copy desired live edits back here and review with Git; no syncing daemon or immutable symlink tree.

- Diff and confirmation before apply.
- Private timestamped backups with a recovery manifest.
- Existing file symlinks are backed up/replaced without modifying their referents.
- Symlinked parent directories and conflicting directories are refused.
- Existing `.zshrc` contents are not printed; review them locally before replacement.
- Backups stay outside this repo: user files under `~/.local/state/arch-setup/backups`, system files under `/var/backups/arch-setup`.
- Normal Git checkouts for Neovim, Doom config, pi config, and OMZ. Existing matching checkouts are retained untouched; unrelated targets are refused.
- No stored passwords, wireless profiles, Tailscale identity, history, or editor/agent caches.

Backups are a safety measure for applying files, not an OS backup. Restoring them is a deliberate manual action after inspecting the manifest and preserving newer edits.

## Hardware profiles

- **MiniBook:** audited N100 model. Limine rotation, kernel orientation, explicit DSI display/touch transforms, and tablet-mode support are documented in [the audit](docs/minibook-audit.md).
- **T14:** placeholder only. Intel/AMD variant, firmware, and display/input behavior must be audited before applying. `make plan HOST=t14` works; mutating targets refuse it.

Ly's console orientation, the disk-unlock/console path, suspend, tablet mode, media keys, external displays, and new kernel updates need manual validation. `make boot-check` is read-only and examines the *currently running* setup; it cannot certify a new boot image.

## Shared-config provenance

Initial Ghostty, tmux, Herdr, Starship and Zsh preferences came from `../dotfiles` at commit `c29b0f9fd93970b4e5a916d05b287f5a1ab297b0`, not live application files. The original macOS repo is untouched.

Linux adaptations:

- Ghostty: removed the macOS Option-key setting; preserved colors/font/shaders.
- tmux: `wl-copy` instead of `pbcopy`; omitted the mandatory macOS-only agent-helper layer and its `/Users/rv` paths. A local optional layer can still be loaded.
- Zsh: OMZ + Starship preserved; Linux Node is managed by pacman rather than adding NVM as a second owner.
- Herdr: preserved config and declared its Vim-navigation plugin separately.

The external personal Doom/Neovim repos are not rewritten. If those repos still enable unused LaTeX features or auto-install language servers through Mason, reconcile them deliberately. This repo installs no TeX distribution. Mason-downloaded executables are not used as a substitute for declared Linux tooling without review.

## Validation limits

Tests write only temporary fixtures, covering package/path validation, backups/idempotence, symlinks, source-checkout conflicts, Paru dispatch and refusal paths, noninteractive refusal, service conflicts, and Lua evaluation with stubbed APIs. They do not start Hyprland or install/build applications. Lint reports tools it cannot run.

Bootloader installation/update integration, Brave/1Password browser integration, Doom build/runtime behavior, Herdr graphics, and hardware acceptance are not certified by these tests. See the runbook for the explicit checkpoints.
