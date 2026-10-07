#!/usr/bin/env bash
# All writes stay in temporary fixtures. No packages/services/live configs touched.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/lib.sh"
PROJECT=$ROOT
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
count=0 failures=0

expect_failure() { if "$@" >/dev/null 2>&1; then return 1; fi; }

test_case() {
  count=$((count + 1))
  if ( "$2" ); then printf 'PASS %s\n' "$1";
  else printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); fi
}

paths() {
  safe_relative .config/hypr/host.lua || return
  safe_relative configs/zsh/zshrc || return
  local path
  for path in /etc/passwd ../escape a/../b a/./b '' 'a b' 'a;touch'; do
    expect_failure safe_relative "$path" || return
  done
}

packages() {
  local -a values=()
  printf '# comment\n git # inline\n\nnodejs-lts-krypton\n' > "$scratch/packages"
  append_packages "$scratch/packages" values || return
  [[ ${values[*]} == 'git nodejs-lts-krypton' ]] || return
  printf 'git\ngit\n' > "$scratch/duplicate"
  expect_failure append_packages "$scratch/duplicate" values || return
  printf 'git;touch /tmp/bad\n' > "$scratch/invalid"
  expect_failure append_packages "$scratch/invalid" values || return
  expect_failure append_packages "$scratch/missing" values || return
}

profiles() {
  HOST=minibook DEV=1 EXTRA='' BOOT_HOOK=0
  load_settings || return
  build_package_lists || return
  [[ $AUDITED == 1 && $LY_TTY == tty2 && $FILESYSTEM == ext4 ]] || return
  local names=" ${OFFICIAL[*]} "
  [[ $names == *' uv '* && $names == *' raylib '* && $names == *' typescript '* ]] || return
  [[ $names != *' docker '* && $names != *' texlive '* && $names != *' go '* && $names != *' networkmanager '* ]] || return
  [[ " ${AUR[*]} " == *' brave-bin '* && " ${AUR[*]} " == *' 1password '* && " ${AUR[*]} " == *' sioyek-appimage '* ]] || return
  DEV=0 EXTRA=go BOOT_HOOK=1
  build_package_lists || return
  [[ " ${OFFICIAL[*]} " != *' raylib '* && " ${OFFICIAL[*]} " == *' go '* ]] || return
  [[ " ${AUR[*]} " == *' limine-mkinitcpio-hook '* ]] || return
  HOST=t14; load_settings || return
  [[ $AUDITED == 0 && ${#HOST_SERVICES[@]} == 0 ]] || return
  HOST=../evil; expect_failure load_settings || return
}

manifest() {
  HOST=minibook
  mkdir -p "$scratch/manifests/home" "$scratch/manifests/system" || return
  load_files user "$scratch/manifests/home" || return
  [[ ${#FILE_ROWS[@]} == 16 ]] || return
  local row
  [[ "${FILE_ROWS[*]}" == *'hosts/minibook/host.lua'* ]] || return
  [[ "${FILE_ROWS[*]}" != *'hosts/t14/host.lua'* ]] || return
  load_files system "$scratch/manifests/system" || return
  [[ ${#FILE_ROWS[@]} == 6 ]] || return
  for row in "${FILE_ROWS[@]}"; do [[ $row == *"$scratch/manifests/system/"* ]] || return; done
}

symlinks() {
  local dir="$scratch/symlinks"
  mkdir -p "$dir/home" "$dir/outside" || return
  ln -s "$dir/outside" "$dir/home/.config" || return
  expect_failure no_symlink_parents "$dir/home/.config/app/file" "$dir/home" || return
  expect_failure no_symlink_parents "$dir/outside/file" "$dir/home" || return
  HOST=minibook
  expect_failure load_files user "$dir/home" || return
  [[ -z $(find "$dir/outside" -mindepth 1 -print) ]] || return
}

copy_and_backup() {
  local dir="$scratch/copies" anchor backup source target row
  mkdir -p "$dir/home" || return
  anchor="$dir/home"
  HOST=minibook
  load_files user "$anchor" || return
  printf 'OLD SHELL WITH PRIVATE VALUE\n' > "$anchor/.zshrc"
  chmod 644 "$anchor/.zshrc"
  copy_files "$anchor" "$anchor/.local/state/arch-setup/backups" > "$dir/log" || return
  cmp -s "$anchor/.zshrc" "$ROOT/configs/zsh/zshrc" || return
  backup=$(find "$anchor/.local/state/arch-setup/backups" -mindepth 1 -maxdepth 1 -type d -print)
  [[ $(stat -c '%a' "$backup") == 700 ]] || return
  [[ $(stat -c '%a' "$backup/manifest.tsv") == 600 ]] || return
  grep -q 'OLD SHELL' "$backup/0-.zshrc" || return
  ! grep -q 'PRIVATE VALUE' "$dir/log" || return
  for row in "${FILE_ROWS[@]}"; do
    IFS=$'\t' read -r source target mode <<< "$row"
    file_same "$source" "$target" "$mode" || return
  done
  copy_files "$anchor" "$anchor/.local/state/arch-setup/backups" >/dev/null || return
  [[ $(find "$anchor/.local/state/arch-setup/backups" -mindepth 1 -maxdepth 1 -type d | wc -l) == 1 ]] || return
}

replace_link_not_referent() {
  local dir="$scratch/link-replacement" source='configs/starship.toml' target mode=0644 backup
  mkdir -p "$dir/home" || return
  printf 'untouched referent\n' > "$dir/elsewhere"
  target="$dir/home/config"
  ln -s "$dir/elsewhere" "$target" || return
  FILE_ROWS=("$source"$'\t'"$target"$'\t'"$mode")
  copy_files "$dir/home" "$dir/home/backups" >/dev/null || return
  [[ ! -L $target ]] || return
  grep -qx 'untouched referent' "$dir/elsewhere" || return
  backup=$(find "$dir/home/backups" -mindepth 1 -maxdepth 1 -type d)
  [[ -L $backup/0-config && $(readlink "$backup/0-config") == "$dir/elsewhere" ]] || return
}

system_link() {
  local dir="$scratch/system-link" source='@/run/systemd/resolve/stub-resolv.conf'
  mkdir -p "$dir/etc" || return
  printf 'old resolver\n' > "$dir/etc/resolv.conf"
  FILE_ROWS=("$source"$'\t'"$dir/etc/resolv.conf"$'\t0644')
  copy_files "$dir" "$dir/backups" >/dev/null || return
  [[ -L $dir/etc/resolv.conf ]] || return
  [[ $(readlink "$dir/etc/resolv.conf") == /run/systemd/resolve/stub-resolv.conf ]] || return
  file_same "$source" "$dir/etc/resolv.conf" 0644 || return
}

preflight_directory_conflict() {
  local dir="$scratch/directory-conflict"
  mkdir -p "$dir/home/.config/ghostty/config" || return
  HOST=minibook
  expect_failure load_files user "$dir/home" || return
  [[ ! -e $dir/home/.zshrc ]] || return
}

shell_privacy() {
  local dir="$scratch/privacy"
  mkdir -p "$dir" || return
  printf 'SECRET_DO_NOT_PRINT\n' > "$dir/.zshrc"
  FILE_ROWS=('configs/zsh/zshrc'$'\t'"$dir/.zshrc"$'\t0644')
  preview_files 1 > "$dir/output" || return
  ! grep -q SECRET_DO_NOT_PRINT "$dir/output" || return
  grep -q suppressed "$dir/output" || return
}

checkout_rules() {
  local dir="$scratch/checkouts" status
  mkdir -p "$dir/repo/child" || return
  git -C "$dir/repo" init -q || return
  git -C "$dir/repo" remote add origin git@github.com:rvdeguzman/nvim.git || return
  checkout_valid "$dir/repo" https://github.com/rvdeguzman/nvim.git || return
  expect_failure checkout_valid "$dir/repo/child" https://github.com/rvdeguzman/nvim.git || return
  expect_failure checkout_valid "$dir/repo" https://github.com/other/repo.git || return
  status=0; checkout_valid "$dir/missing" https://example.com/repo.git || status=$?
  [[ $status == 2 ]] || return
}

aur_review_does_not_execute() {
  local dir="$scratch/aur"
  mkdir "$dir" || return
  git -C "$dir" init -q || return
  git -C "$dir" remote add origin https://aur.archlinux.org/hunk.git || return
  printf 'touch SHOULD_NOT_EXIST\n' > "$dir/PKGBUILD"
  printf 'touch ALSO_SHOULD_NOT_EXIST\n' > "$dir/hunk.install"
  git -C "$dir" add . || return
  git -C "$dir" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture || return
  AUR_DIR=$dir PACKAGE=hunk
  review_aur > "$scratch/aur-review-output" || return
  [[ ! -e $dir/SHOULD_NOT_EXIST && ! -e $dir/ALSO_SHOULD_NOT_EXIST ]] || return
}

service_conflicts() {
  systemctl() {
    if [[ $1 == is-enabled && $2 == NetworkManager.service ]]; then printf 'enabled\n'; return 0; fi
    printf 'inactive\n'; return 1
  }
  expect_failure require_no_conflicts || return
  systemctl() { printf 'inactive\n'; return 1; }
  require_no_conflicts || return
}

noninteractive_refusal() {
  expect_failure confirm 'must not run' INSTALL </dev/null || return
}

plan_is_readonly() {
  mkdir "$scratch/plan-home" || return
  HOME="$scratch/plan-home" HOST=minibook DEV=1 EXTRA='' BOOT_HOOK=0 "$PROJECT/setup" plan > "$scratch/plan-output" || return
  [[ -z $(find "$scratch/plan-home" -mindepth 1 -print) ]] || return
  grep -q brave-bin "$scratch/plan-output" || return
  grep -q 'filesystem=ext4' "$scratch/plan-output" || return
  expect_failure env HOST=../evil "$PROJECT/setup" plan || return
  expect_failure env HOST=minibook DEV=maybe "$PROJECT/setup" plan || return
}

lua_configuration() {
  if ! command -v luajit >/dev/null 2>&1; then printf 'SKIP Lua behavioral test: luajit missing\n'; return 0; fi
  mkdir -p "$scratch/lua-home/.config/hypr" || return
  cp "$PROJECT/hosts/minibook/host.lua" "$scratch/lua-home/.config/hypr/host.lua" || return
  HOME="$scratch/lua-home" XDG_CONFIG_HOME="$scratch/lua-home/.config" luajit "$PROJECT/tests/hypr-stub.lua" "$PROJECT/configs/hypr/hyprland.lua" || return
}

omarchy_guard() {
  if [[ ! -f /etc/arch-release ]]; then printf 'SKIP Arch-specific Omarchy guard\n'; return 0; fi
  HOME_DIR="$scratch/omarchy-home"
  mkdir -p "$HOME_DIR/.local/share/omarchy" || return
  AUDITED=1 PRODUCT_NAME='' CPU_MATCH=''
  if require_fresh_arch > "$scratch/guard-output" 2>&1; then return 1; fi
  grep -q 'Refusing to mutate Omarchy' "$scratch/guard-output" || return
}

aur_selection() {
  HOST=minibook DEV=1 EXTRA='' BOOT_HOOK=0
  build_package_lists || return
  HOME_DIR="$scratch/aur-selection-home"
  mkdir "$HOME_DIR" || return
  PACKAGE=hunk
  validate_aur_package || return
  [[ $AUR_DIR == "$HOME_DIR/.cache/arch-setup/aur/hunk" ]] || return
  PACKAGE=../../escape
  expect_failure validate_aur_package || return
  PACKAGE=undeclared-package
  expect_failure validate_aur_package || return
  [[ ! -e $HOME_DIR/.cache ]] || return
}

mode_only_change() {
  local dir="$scratch/mode-change" source='configs/starship.toml' target
  mkdir "$dir" || return
  target="$dir/config"
  cp "$ROOT/$source" "$target" || return
  chmod 600 "$target" || return
  expect_failure file_same "$source" "$target" 0644 || return
  FILE_ROWS=("$source"$'\t'"$target"$'\t0644')
  copy_files "$dir" "$dir/backups" >/dev/null || return
  file_same "$source" "$target" 0644 || return
}

dangling_link_backup() {
  local dir="$scratch/dangling" target backup
  mkdir "$dir" || return
  target="$dir/config"
  ln -s "$dir/missing-referent" "$target" || return
  FILE_ROWS=('configs/starship.toml'$'\t'"$target"$'\t0644')
  copy_files "$dir" "$dir/backups" >/dev/null || return
  backup=$(find "$dir/backups" -mindepth 1 -maxdepth 1 -type d)
  [[ -L $backup/0-config && ! -e $backup/0-config ]] || return
  [[ -f $target && ! -L $target && ! -e $dir/missing-referent ]] || return
}

test_case 'safe manifest paths' paths
test_case 'package comments, duplicates and invalid entries' packages
test_case 'profiles and optional development/Go/boot hook' profiles
test_case 'complete scoped manifests' manifest
test_case 'reject symlinked parents and escaped targets' symlinks
test_case 'copy, private backups and idempotence' copy_and_backup
test_case 'replace a symlink without touching referent' replace_link_not_referent
test_case 'resolver symlink and old-file backup' system_link
test_case 'directory conflict rejected before writes' preflight_directory_conflict
test_case 'existing shell contents never printed' shell_privacy
test_case 'matching Git origin and checkout-root checks' checkout_rules
test_case 'AUR review never executes scripts' aur_review_does_not_execute
test_case 'reject competing network managers' service_conflicts
test_case 'refuse unattended mutation' noninteractive_refusal
test_case 'plan makes no HOME changes' plan_is_readonly
test_case 'Lua config evaluates with stubbed APIs, no app launches' lua_configuration
test_case 'refuse mutating an Omarchy installation' omarchy_guard
test_case 'AUR names restricted to declared package list' aur_selection
test_case 'mode-only changes are backed up and applied' mode_only_change
test_case 'dangling symlinks backed up without dereferencing' dangling_link_backup
printf '\n%d tests; %d failures\n' "$count" "$failures"
(( failures == 0 ))
