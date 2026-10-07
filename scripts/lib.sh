#!/usr/bin/env bash
# Shared Bash helpers. Sourcing this file performs no system changes.

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

die() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

safe_relative() {
  local value=$1 part
  [[ $value =~ ^[a-zA-Z0-9_.@+-]+(/[a-zA-Z0-9_.@+-]+)*$ ]] || {
    die "Unsafe relative path: $value"; return 1;
  }
  local -a parts
  IFS=/ read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do
    [[ $part != . && $part != .. ]] || { die "Unsafe path component: $value"; return 1; }
  done
}

load_settings() {
  HOST=${HOST:-minibook}
  DEV=${DEV:-1}
  EXTRA=${EXTRA:-}
  PACKAGE=${PACKAGE:-}
  BOOT_HOOK=${BOOT_HOOK:-0}
  [[ $HOST =~ ^[a-z0-9][a-z0-9-]*$ && -f $ROOT/hosts/$HOST/host.sh ]] || {
    die "Unknown/invalid HOST: $HOST"; return 1;
  }
  [[ $DEV == 0 || $DEV == 1 ]] || { die 'DEV must be 0 or 1'; return 1; }
  [[ -z $EXTRA || $EXTRA == go ]] || { die 'Only EXTRA=go is supported'; return 1; }
  [[ $BOOT_HOOK == 0 || $BOOT_HOOK == 1 ]] || { die 'BOOT_HOOK must be 0 or 1'; return 1; }
  HOME_DIR=$(cd -- "${ARCH_SETUP_USER_HOME:-$HOME}" && pwd -P)
  # These are trusted configuration files in this repository, not downloaded code.
  # shellcheck source=/dev/null
  source "$ROOT/hosts/$HOST/host.sh"
  [[ $LY_TTY =~ ^tty[1-6]$ ]] || { die 'Invalid Ly TTY'; return 1; }
}

append_packages() {
  local file=$1 array_name=$2 line package existing
  local -n result=$array_name
  local -A seen_here=()
  while IFS= read -r line || [[ -n $line ]]; do
    package=$(trim "${line%%#*}")
    [[ -n $package ]] || continue
    [[ $package =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || { die "Invalid package in $file: $package"; return 1; }
    [[ ! ${seen_here[$package]+present} ]] || { die "Duplicate package in $file: $package"; return 1; }
    seen_here[$package]=1
    existing=0
    local entry
    for entry in "${result[@]}"; do [[ $entry != "$package" ]] || existing=1; done
    (( existing )) || result+=("$package")
  done < "$file"
}

build_package_lists() {
  OFFICIAL=() AUR=()
  local group
  for group in base desktop workspace; do
    append_packages "$ROOT/packages/$group.txt" OFFICIAL || return
  done
  if [[ $DEV == 1 ]]; then append_packages "$ROOT/packages/development.txt" OFFICIAL || return; fi
  if [[ $EXTRA == go ]]; then append_packages "$ROOT/packages/optional-go.txt" OFFICIAL || return; fi
  append_packages "$ROOT/hosts/$HOST/packages.txt" OFFICIAL || return
  append_packages "$ROOT/packages/aur.txt" AUR || return
  append_packages "$ROOT/hosts/$HOST/aur.txt" AUR || return
  if [[ $BOOT_HOOK == 1 ]]; then append_packages "$ROOT/packages/optional-boot-aur.txt" AUR || return; fi
}

no_symlink_parents() {
  local target=$1 anchor=$2 current
  [[ $target == "$anchor/"* || $anchor == / && $target == /* ]] || {
    die "Target escaped its scope: $target"; return 1;
  }
  current=${target%/*}
  while :; do
    [[ ! -L $current ]] || { die "Refusing symlinked parent: $current"; return 1; }
    [[ ! -e $current || -d $current ]] || { die "Parent is not a directory: $current"; return 1; }
    [[ $current != "$anchor" && $current != / ]] || break
    current=${current%/*}
    [[ -n $current ]] || current=/
  done
}

# Fields: scope, host (all or named profile), source or @symlink, target, mode.
# All targets are relative to HOME (user) or / (system); no arbitrary directory copies.
load_files() {
  local scope=$1 anchor=$2 row_scope profile source target mode extra
  FILE_ROWS=()
  while IFS=$'\t' read -r row_scope profile source target mode extra || [[ -n $row_scope ]]; do
    [[ -n $row_scope && $row_scope != \#* ]] || continue
    [[ $row_scope == "$scope" && ( $profile == all || $profile == "$HOST" ) ]] || continue
    [[ -z $extra ]] || { die 'Extra manifest columns'; return 1; }
    safe_relative "$target" || return
    [[ $mode =~ ^0[0-7]{3}$ ]] || { die "Invalid file mode: $mode"; return 1; }
    if [[ $source == @* ]]; then
      [[ $scope == system && $source == @/run/systemd/resolve/stub-resolv.conf ]] || {
        die "Unapproved symlink source: $source"; return 1;
      }
    else
      safe_relative "$source" || return
      [[ -f $ROOT/$source && ! -L $ROOT/$source ]] || { die "Missing/unsafe source: $source"; return 1; }
      no_symlink_parents "$ROOT/$source" "$ROOT" || return
    fi
    target="${anchor%/}/$target"
    no_symlink_parents "$target" "$anchor" || return
    [[ ! -d $target || -L $target ]] || { die "Refusing to replace directory: $target"; return 1; }
    local existing old_source old_target old_mode
    for existing in "${FILE_ROWS[@]}"; do
      IFS=$'\t' read -r old_source old_target old_mode <<< "$existing"
      [[ $old_target != "$target" ]] || { die "Duplicate target: $target"; return 1; }
    done
    FILE_ROWS+=("$source"$'\t'"$target"$'\t'"$mode")
  done < "$ROOT/configs/files.tsv"
}

file_same() {
  local source=$1 target=$2 mode=$3
  if [[ $source == @* ]]; then
    [[ -L $target && $(readlink -- "$target") == "${source#@}" ]]
  else
    [[ -f $target && ! -L $target ]] && cmp -s -- "$ROOT/$source" "$target" &&
      [[ $(stat -c '%a' -- "$target") == "${mode#0}" ]]
  fi
}

preview_files() {
  local show_diff=${1:-0} row source target mode status
  for row in "${FILE_ROWS[@]}"; do
    IFS=$'\t' read -r source target mode <<< "$row"
    if file_same "$source" "$target" "$mode"; then printf 'UNCHANGED %s\n' "$target"; continue; fi
    printf 'CHANGE %s <- %s\n' "$target" "$source"
    [[ $show_diff == 1 && $source != @* && ! -L $target ]] || continue
    if [[ ${target##*/} == .zshrc ]]; then
      printf '  Existing shell contents suppressed: inspect locally before approval.\n'
      continue
    fi
    status=0
    if [[ -e $target ]]; then
      diff -u -- "$target" "$ROOT/$source" || status=$?
    else
      diff -u -- /dev/null "$ROOT/$source" || status=$?
    fi
    (( status <= 1 )) || { die "Could not diff $target"; return 1; }
  done
}

copy_files() {
  local anchor=$1 backup_base=$2 row source target mode backup='' saved temp index=0
  # Call load_files before this: every target is preflighted before any changes.
  no_symlink_parents "$backup_base/placeholder" "$anchor" || return
  for row in "${FILE_ROWS[@]}"; do
    IFS=$'\t' read -r source target mode <<< "$row"
    file_same "$source" "$target" "$mode" && continue
    no_symlink_parents "$target" "$anchor" || return
    [[ ! -d $target || -L $target ]] || { die "Refusing directory: $target"; return 1; }
    if [[ -z $backup ]]; then
      (umask 077; mkdir -p -- "$backup_base") || return
      backup=$(mktemp -d "$backup_base/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX") || return
      chmod 700 -- "$backup" || return
    fi
    saved=none
    if [[ -e $target || -L $target ]]; then
      saved="$backup/$index-${target##*/}"
      cp -a -- "$target" "$saved" || return
      [[ -L $saved ]] || chmod 600 -- "$saved" || return
    fi
    mkdir -p -- "${target%/*}" || return
    temp=$(mktemp "${target%/*}/.arch-setup-XXXXXX") || return
    if [[ $source == @* ]]; then
      rm -- "$temp" || return
      ln -s -- "${source#@}" "$temp" || return
    else
      if ! install -m "$mode" -- "$ROOT/$source" "$temp"; then rm -f -- "$temp"; return 1; fi
    fi
    # Replace the target itself, not the referent of an existing symlink.
    if ! mv -T -- "$temp" "$target"; then rm -f -- "$temp"; return 1; fi
    printf '%s\t%s\n' "$target" "$saved" >> "$backup/manifest.tsv" || return
    chmod 600 -- "$backup/manifest.tsv" || return
    printf 'COPIED %s\n' "$target"
    index=$((index + 1))
  done
  if [[ -n $backup ]]; then printf 'Private backups/recovery manifest: %s\n' "$backup";
  else printf 'All managed files already match.\n'; fi
}

confirm() {
  local message=$1 token=$2 answer
  [[ -t 0 ]] || { die 'An interactive terminal is required; there is no unattended --yes'; return 1; }
  printf '%s\nType %q to continue: ' "$message" "$token"
  IFS= read -r answer || return
  [[ $answer == "$token" ]] || { die 'Cancelled'; return 1; }
}

require_fresh_arch() {
  [[ $(uname -s) == Linux && -f /etc/arch-release ]] || { die 'Fresh Arch Linux required'; return 1; }
  if command -v omarchy >/dev/null 2>&1 || [[ -d $HOME_DIR/.local/share/omarchy ]]; then
    die 'Refusing to mutate Omarchy: this repo is for fresh plain Arch'; return 1
  fi
  [[ $AUDITED == 1 ]] || { die 'Host hardware audit is pending; only planning is allowed'; return 1; }
  local product
  IFS= read -r product < /sys/class/dmi/id/product_name
  [[ -z $PRODUCT_NAME || $product == "$PRODUCT_NAME" ]] || { die 'Hardware model does not match profile'; return 1; }
  [[ -z $CPU_MATCH ]] || grep -Fq -- "$CPU_MATCH" /proc/cpuinfo || { die 'CPU does not match profile'; return 1; }
}

require_user() { (( EUID != 0 )) || { die 'Run make as your normal user; system stages use sudo'; return 1; }; }

checkout_valid() {
  local path=$1 expected=$2 top origin
  [[ -e $path || -L $path ]] || return 2
  [[ -d $path && ! -L $path ]] || { die "Conflicting checkout: $path"; return 1; }
  top=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || { die "Not a Git checkout root: $path"; return 1; }
  [[ $(realpath -- "$top") == "$(realpath -- "$path")" ]] || { die "Nested checkout target: $path"; return 1; }
  origin=$(git -C "$path" remote get-url origin) || return
  origin=${origin%.git}; expected=${expected%.git}
  origin=${origin/#git@github.com:/https:\/\/github.com\/}
  [[ $origin == "$expected" ]] || { die "Unexpected origin: $path"; return 1; }
}

service_names() {
  SERVICES=(iwd.service systemd-networkd.service systemd-resolved.service systemd-timesyncd.service
    bluetooth.service tailscaled.service "${HOST_SERVICES[@]}" "ly@$LY_TTY.service")
}

require_no_conflicts() {
  local unit enabled active
  for unit in NetworkManager.service dhcpcd.service sddm.service gdm.service lightdm.service greetd.service; do
    enabled=$(systemctl is-enabled "$unit" 2>/dev/null || true)
    active=$(systemctl is-active "$unit" 2>/dev/null || true)
    if [[ $enabled == enabled* || $enabled == linked* || $active == active ]]; then
      die "Review/disable competing service first: $unit"; return 1
    fi
  done
}

validate_aur_package() {
  local entry found=0
  for entry in "${AUR[@]}"; do [[ $entry != "$PACKAGE" ]] || found=1; done
  (( found )) || { die 'PACKAGE must be an entry in the selected AUR lists'; return 1; }
  AUR_DIR="$HOME_DIR/.cache/arch-setup/aur/$PACKAGE"
  no_symlink_parents "$AUR_DIR" "$HOME_DIR" || return
}

review_aur() {
  checkout_valid "$AUR_DIR" "https://aur.archlinux.org/$PACKAGE.git" || return
  [[ -z $(git -C "$AUR_DIR" status --porcelain --untracked-files=no) ]] || {
    die 'Tracked AUR files are modified; inspect separately'; return 1;
  }
  printf 'AUR revision: '; git -C "$AUR_DIR" rev-parse HEAD || return
  local script
  [[ -f $AUR_DIR/PKGBUILD && ! -L $AUR_DIR/PKGBUILD ]] || { die 'Missing/unsafe PKGBUILD'; return 1; }
  for script in "$AUR_DIR/PKGBUILD" "$AUR_DIR"/*.install; do
    [[ -e $script || -L $script ]] || continue
    [[ -f $script && ! -L $script ]] || { die 'Unsafe install script'; return 1; }
    printf '\n=== %s ===\n' "${script##*/}"
    # Display only public build scripts; never source them during review.
    while IFS= read -r line || [[ -n $line ]]; do printf '%s\n' "$line"; done < "$script"
  done
  printf 'Inspect patches/other files too. AUR scripts execute arbitrary code; this is not security verification.\n'
}
