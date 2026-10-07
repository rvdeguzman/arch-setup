# Arch setup agent instructions

Read README.md and docs/install.md before proposing installation actions.

- This repository is for fresh plain Arch installs, not in-place Omarchy removal.
- Creating/editing the repo does not authorize installing packages or applying it.
- Use plain Bash for installation scripts and Bash tests; do not introduce Python/Zsh as a bootstrap runtime or an installer framework.
- Use make targets. Plan/diff/check are read-only. Running a mutating target authorizes that stage; execute without custom confirmation prompts and preserve native tool prompts.
- Preserve user changes. Back up existing target files before explicit copy/apply.
- No disk partitioning/formatting, bootloader installation, reboot, or account changes are automated.
- Package lists describe intent, not the full dependency closure or pinned versions.
- Official packages, AUR packages, and external installers are separate make stages.
- Keep Paru's AUR build-script review enabled. The helper bootstrap prints PKGBUILD/install scripts before makepkg. Never build as root.
- Keep credentials, wireless profiles, Tailscale state, history and sessions outside Git.
- The macOS dotfiles repo was the source for shared preferences. Never substitute live machine configs as shared source of truth. Hardware audit files are a separate exception.
- T14 hardware is unaudited: mutating targets must refuse that profile for now.
- Hyprland Lua APIs are version-sensitive. Consult matching official docs/sample before changes. Never reload the current Omarchy session to test this repo.
- Do not source ~/.local/share/omarchy or introduce chezmoi/Home Manager.
- Run make test and make lint; report tests skipped because a tool is absent.
