#!/usr/bin/env bash
# Sourced by setup install. Stages run in separate Bash processes, strictly in order.

install_preflight() {
  [[ -z $PACKAGE ]] || { die 'make install requires the full package selection; use make aur PACKAGE=name separately'; return 1; }
  [[ $BOOT_HOOK == 0 ]] || { die 'Boot hooks require separate review; use the explicit AUR stage, not make install BOOT_HOOK=1'; return 1; }
  [[ ${XDG_CONFIG_HOME:-$HOME_DIR/.config} == "$HOME_DIR/.config" ]] || {
    die 'Initial profile targets ~/.config; review custom XDG paths first'; return 1;
  }
  local cmd path status
  for cmd in git sudo; do
    command -v "$cmd" >/dev/null 2>&1 || { die "Prerequisite missing: $cmd"; return 1; }
  done
  require_no_conflicts || return
  load_files user "$HOME_DIR" || return
  load_files system / || return
  no_symlink_parents "$HOME_DIR/.local/state/arch-setup/backups/placeholder" "$HOME_DIR" || return
  validate_source_checkouts || return
  validate_doom_core || return
  if ! command -v herdr >/dev/null 2>&1; then
    path="$HOME_DIR/.cache/arch-setup/herdr-install.sh"
    no_symlink_parents "$path" "$HOME_DIR" || return
    [[ ! -e $path && ! -L $path || -f $path && ! -L $path ]] || {
      die 'Unsafe/conflicting cached Herdr installer'; return 1;
    }
  fi
  if ! command -v paru >/dev/null 2>&1; then
    path="$HOME_DIR/.cache/arch-setup/paru"
    no_symlink_parents "$path" "$HOME_DIR" || return
    status=0; checkout_valid "$path" https://aur.archlinux.org/paru.git || status=$?
    case $status in
      0)
        [[ -z $(git -C "$path" status --porcelain --untracked-files=no) ]] || {
          die 'Tracked Paru build files are modified; inspect separately'; return 1;
        }
        ;;
      2) ;;
      *) return "$status" ;;
    esac
  fi
}

run_install_stage() {
  local stage=$1 status
  printf '\n=== [%s/%s] %s ===\n' "$INSTALL_INDEX" "$INSTALL_TOTAL" "$stage"
  # A separate process retains errexit inside the stage even when we capture failure here.
  if "$ROOT/setup" "$stage"; then return 0; else status=$?; fi
  printf '\nStage %s failed (exit %s). Installation stopped; no later stages ran.\n' "$stage" "$status" >&2
  printf 'Inspect the error/backups, then retry: make install HOST=%q DEV=%q EXTRA=%q\n' "$HOST" "$DEV" "$EXTRA" >&2
  printf 'To troubleshoot just this stage: make %s HOST=%q DEV=%q EXTRA=%q\n' "$stage" "$HOST" "$DEV" "$EXTRA" >&2
  return "$status"
}

install_run() {
  local stage
  local -a stages=(packages paru aur sources diff apply-user apply-system pi herdr herdr-plugins doom services check)
  printf 'Installing for %s (HOST=%s). Native prompts and AUR review remain interactive.\n' "$HOST_NAME" "$HOST"
  printf 'Preflight: checking conflicts and existing paths before any installation.\n'
  install_preflight
  export HOST DEV EXTRA PACKAGE BOOT_HOOK
  INSTALL_INDEX=0 INSTALL_TOTAL=${#stages[@]}
  for stage in "${stages[@]}"; do
    INSTALL_INDEX=$((INSTALL_INDEX + 1))
    run_install_stage "$stage"
  done
  printf '\nSetup stages completed. Services are enabled for the next boot, not started.\n'
  printf '%s\n' \
    'Before rebooting: inspect Limine/UKI layout and kernel-update integration (docs/install.md).' \
    'Boot rotation/rebuild, login-shell changes, Wi-Fi association, and account sign-ins remain explicit/manual.' \
    'Reboot manually only when the boot checkpoint is satisfied; then run make check and make boot-check.' \
    'Verify display/touch rotation, suspend, tablet mode, and application integration using the runbook.'
}
