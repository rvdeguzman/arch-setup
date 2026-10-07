#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
cd -- "$ROOT"

bash -n setup scripts/*.sh tests/*.sh hosts/*/host.sh
load_settings
build_package_lists
# Validate every declared host's package lists and file targets in temporary roots.
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
mkdir "$temp/home" "$temp/system"
for HOST in minibook t14; do
  load_settings
  build_package_lists
  load_files user "$temp/home"
  load_files system "$temp/system"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck setup scripts/*.sh tests/*.sh hosts/*/host.sh
else printf 'SKIP ShellCheck: not installed\n'; fi
if command -v zsh >/dev/null 2>&1; then
  zsh -n configs/zsh/zshrc
else printf 'SKIP Zsh syntax: not installed\n'; fi
if command -v luajit >/dev/null 2>&1; then
  for file in configs/hypr/*.lua hosts/*/*.lua; do luajit -b "$file" /dev/null; done
elif command -v luac >/dev/null 2>&1; then
  for file in configs/hypr/*.lua hosts/*/*.lua; do luac -p "$file"; done
else printf 'SKIP Lua syntax: no Lua compiler installed\n'; fi
if command -v jq >/dev/null 2>&1; then
  jq empty configs/waybar/config.json
else printf 'SKIP Waybar JSON: jq not installed\n'; fi
printf 'Static checks passed. No live configs applied or reloaded.\n'
