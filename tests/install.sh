#!/usr/bin/env bash
# All installer effects are mocked in temporary copies; never install on the real host.
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

# These override identity reads only, leaving the real detection logic intact.
hardware_product() { printf '%s\n' "${TEST_PRODUCT:-MiniBook X}"; }
hardware_cpu_matches() { [[ ${TEST_CPU:-N100} == "$1" ]]; }

detection() {
  [[ $(detect_host) == minibook ]] || return
  HOST=auto; load_settings || return
  [[ $HOST == minibook && $AUDITED == 1 ]] || return
  TEST_PRODUCT=unknown; expect_failure detect_host || return
  TEST_PRODUCT='MiniBook X' TEST_CPU=N5100; expect_failure detect_host || return
  TEST_CPU=N100 TEST_PRODUCT='ThinkPad T14 Gen 2'; expect_failure detect_host || return
  TEST_PRODUCT='MiniBook X'
  mkdir -p "$scratch/ambiguous/hosts/one" "$scratch/ambiguous/hosts/two" || return
  cp "$PROJECT/hosts/minibook/host.sh" "$scratch/ambiguous/hosts/one/host.sh" || return
  cp "$PROJECT/hosts/minibook/host.sh" "$scratch/ambiguous/hosts/two/host.sh" || return
  ROOT="$scratch/ambiguous"; expect_failure detect_host || return
  printf 'AUDITED=0\n' >> "$ROOT/hosts/one/host.sh"
  printf 'AUDITED=0\n' >> "$ROOT/hosts/two/host.sh"
  expect_failure detect_host || return
}

prepare_fixture() {
  local dir=$1
  mkdir -p "$dir/project" "$dir/home" || return
  cp -R "$PROJECT/setup" "$PROJECT/Makefile" "$PROJECT/scripts" "$PROJECT/packages" "$PROJECT/hosts" "$PROJECT/configs" "$PROJECT/system" "$PROJECT/sources.tsv" "$dir/project/" || return
  # Intercept child stages only, so real install dispatch, preflight and failure handling run.
  {
    printf '#!/usr/bin/env bash\n'
    cat <<'SHIM'
if [[ ${INSTALL_TEST_STUB_STAGES:-0} == 1 && ${1:-} != install ]]; then
  printf '%s\n' "$1" >> "$INSTALL_TEST_LOG"
  [[ ${1:-} != "${INSTALL_TEST_FAIL:-}" ]] || exit 23
  exit 0
fi
SHIM
    tail -n +2 "$PROJECT/setup"
  } > "$dir/project/setup"
  chmod +x "$dir/project/setup" || return
  cat >> "$dir/project/scripts/lib.sh" <<'MOCKS'
hardware_product() { printf '%s\n' "${TEST_PRODUCT:-MiniBook X}"; }
hardware_cpu_matches() { [[ ${TEST_CPU:-N100} == "$1" ]]; }
require_fresh_arch() {
  [[ ${TEST_ARCH:-1} == 1 && $AUDITED == 1 ]] || { die 'Fresh audited Arch required'; return 1; }
  [[ $(hardware_product) == "$PRODUCT_NAME" ]] && hardware_cpu_matches "$CPU_MATCH" || { die 'Hardware mismatch'; return 1; }
}
require_user() { [[ ${TEST_USER:-1} == 1 ]]; }
systemctl() {
  if [[ ${TEST_CONFLICT:-0} == 1 && $1 == is-enabled && $2 == NetworkManager.service ]]; then printf 'enabled\n'; return 0; fi
  printf 'inactive\n'; return 1
}
command() {
  if [[ $1 == -v ]]; then
    case $2 in
      sudo) printf '/mock/sudo\n'; return 0 ;;
      paru) return 1 ;;
      herdr|pi) [[ -x $HOME_DIR/.local/bin/$2 ]] || return 1 ;;
    esac
  fi
  builtin command "$@"
}
curl() {
  local output=''
  while (( $# )); do
    if [[ $1 == --output ]]; then output=$2; shift; fi
    shift
  done
  printf 'mock complete installer\n' > "$output"
  return "${TEST_CURL_STATUS:-0}"
}
herdr() {
  if [[ $1 == plugin && $2 == list ]]; then printf '%s\n' "$TEST_PLUGIN_JSON";
  else printf '%s\n' "$*" >> "$INSTALL_TEST_LOG"; fi
}
npm() { printf 'npm %s\n' "$*" >> "$INSTALL_TEST_LOG"; }
MOCKS
  export HOME="$dir/home" HOST=auto DEV=1 EXTRA='' PACKAGE='' BOOT_HOOK=0
  export PATH=/usr/bin:/bin
  export INSTALL_TEST_LOG="$dir/log" INSTALL_TEST_STUB_STAGES=1
  unset ARCH_SETUP_USER_HOME XDG_CONFIG_HOME HYPRLAND_INSTANCE_SIGNATURE
}

sequence() {
  local dir="$scratch/sequence"
  prepare_fixture "$dir" || return
  make -C "$dir/project" -j8 install > "$dir/output" || return
  printf '%s\n' packages paru aur sources diff apply-user apply-system pi herdr herdr-plugins doom services check > "$dir/expected"
  cmp -s "$dir/expected" "$dir/log" || return
  grep -q 'HOST=minibook' "$dir/output" || return
  grep -q 'Before rebooting' "$dir/output" || return
}

auto_plan_readonly() {
  local dir="$scratch/auto-plan"
  prepare_fixture "$dir" || return
  INSTALL_TEST_STUB_STAGES=0 "$dir/project/setup" plan > "$dir/output" || return
  grep -q 'CHUWI MiniBook X N100' "$dir/output" || return
  [[ ! -e $dir/log && -z $(find "$HOME" -mindepth 1 -print) ]] || return
}

stage_failure() {
  local dir="$scratch/failure" status=0
  prepare_fixture "$dir" || return
  DEV=0 EXTRA=go INSTALL_TEST_FAIL=aur "$dir/project/setup" install > "$dir/output" 2>&1 || status=$?
  [[ $status == 23 ]] || return
  printf '%s\n' packages paru aur > "$dir/expected"
  cmp -s "$dir/expected" "$dir/log" || return
  grep -q 'Stage aur failed (exit 23)' "$dir/output" || return
  grep -q 'make install HOST=minibook DEV=0 EXTRA=go' "$dir/output" || return
  ! grep -q 'Setup stages completed' "$dir/output" || return
}

preflight_refusals() {
  local dir="$scratch/refusals"
  prepare_fixture "$dir" || return
  expect_failure env TEST_PRODUCT=unknown "$dir/project/setup" install || return
  expect_failure env TEST_CPU=N5100 "$dir/project/setup" install || return
  expect_failure env HOST=t14 "$dir/project/setup" install || return
  expect_failure env HOST=minibook TEST_PRODUCT=unknown "$dir/project/setup" install || return
  expect_failure env TEST_ARCH=0 "$dir/project/setup" install || return
  expect_failure env TEST_USER=0 "$dir/project/setup" install || return
  expect_failure env TEST_CONFLICT=1 "$dir/project/setup" install || return
  expect_failure env PACKAGE=hunk "$dir/project/setup" install || return
  expect_failure env BOOT_HOOK=1 "$dir/project/setup" install || return
  expect_failure env XDG_CONFIG_HOME="$dir/custom" "$dir/project/setup" install || return
  [[ ! -e $dir/log ]] || return
  mkdir -p "$HOME/.config/nvim" || return
  expect_failure "$dir/project/setup" install || return
  rmdir "$HOME/.config/nvim" || return
  mkdir -p "$HOME/.config/emacs" || return
  expect_failure "$dir/project/setup" install || return
  rmdir "$HOME/.config/emacs" "$HOME/.config" || return
  mkdir -p "$dir/outside" || return
  ln -s "$dir/outside" "$HOME/.config" || return
  expect_failure "$dir/project/setup" install || return
  [[ ! -e $dir/log && -z $(find "$dir/outside" -mindepth 1 -print) ]] || return
}

herdr_cache() {
  local dir="$scratch/cache" cached
  prepare_fixture "$dir" || return
  export INSTALL_TEST_STUB_STAGES=0
  cached="$HOME/.cache/arch-setup/herdr-install.sh"
  "$dir/project/setup" herdr-fetch > "$dir/output" || return
  [[ -f $cached ]] || return
  printf 'previously reviewed installer\n' > "$cached"
  "$dir/project/setup" herdr-fetch > "$dir/output" || return
  grep -q 'Keeping cached' "$dir/output" || return
  grep -qx 'previously reviewed installer' "$cached" || return
  rm "$cached" || return
  printf 'referent preserved\n' > "$dir/referent"
  ln -s "$dir/referent" "$cached" || return
  expect_failure "$dir/project/setup" herdr-fetch || return
  grep -qx 'referent preserved' "$dir/referent" || return
  rm "$cached" || return
  expect_failure env TEST_CURL_STATUS=29 "$dir/project/setup" herdr-fetch || return
  [[ ! -e $cached && -z $(find "${cached%/*}" -name '.herdr-install-*' -print) ]] || return
}

herdr_combined() {
  local dir="$scratch/herdr-combined" cached
  prepare_fixture "$dir" || return
  export INSTALL_TEST_STUB_STAGES=0
  cached="$HOME/.cache/arch-setup/herdr-install.sh"
  mkdir -p "${cached%/*}" || return
  cat > "$cached" <<'INSTALLER'
#!/bin/sh
printf 'fixture installer executed\n' >> "$INSTALL_TEST_LOG"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/herdr"
chmod +x "$HOME/.local/bin/herdr"
INSTALLER
  "$dir/project/setup" herdr > "$dir/output" || return
  grep -q 'Keeping cached Herdr installer' "$dir/output" || return
  grep -q 'Executing the downloaded Herdr installer' "$dir/output" || return
  [[ -x $HOME/.local/bin/herdr ]] || return
  "$dir/project/setup" herdr > "$dir/output" || return
  printf 'fixture installer executed\n' > "$dir/expected"
  cmp -s "$dir/expected" "$dir/log" || return
  grep -q 'Existing Herdr preserved' "$dir/output" || return
}

existing_apps() {
  local dir="$scratch/existing-apps"
  prepare_fixture "$dir" || return
  export INSTALL_TEST_STUB_STAGES=0
  mkdir -p "$HOME/.local/bin" || return
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/pi"
  cp "$HOME/.local/bin/pi" "$HOME/.local/bin/herdr" || return
  chmod +x "$HOME/.local/bin/pi" "$HOME/.local/bin/herdr" || return
  "$dir/project/setup" pi > "$dir/pi-output" || return
  "$dir/project/setup" herdr > "$dir/herdr-output" || return
  grep -q 'Existing pi preserved' "$dir/pi-output" || return
  grep -q 'Existing Herdr preserved' "$dir/herdr-output" || return
  [[ ! -e $dir/log && ! -e $HOME/.cache ]] || return
}

plugin_reruns() {
  if ! command -v jq >/dev/null 2>&1; then printf 'SKIP Herdr plugin fixtures: jq missing\n'; return 0; fi
  local dir="$scratch/plugins"
  prepare_fixture "$dir" || return
  export INSTALL_TEST_STUB_STAGES=0
  export TEST_PLUGIN_JSON='{"result":{"plugins":[{"plugin_id":"vim-herdr-navigation","enabled":false,"source":{"kind":"github","owner":"paulbkim-dev","repo":"vim-herdr-navigation"}}]}}'
  "$dir/project/setup" herdr-plugins > "$dir/output" || return
  [[ ! -e $dir/log ]] || return
  grep -q 'enabled/disabled preference' "$dir/output" || return
  TEST_PLUGIN_JSON='{"result":{"plugins":[{"plugin_id":"vim-herdr-navigation","source":{"kind":"local"}}]}}'
  expect_failure "$dir/project/setup" herdr-plugins || return
  TEST_PLUGIN_JSON='{"result":{}}'
  expect_failure "$dir/project/setup" herdr-plugins || return
  [[ ! -e $dir/log ]] || return
  TEST_PLUGIN_JSON='{"result":{"plugins":[]}}'
  "$dir/project/setup" herdr-plugins > "$dir/output" || return
  grep -qx 'plugin install paulbkim-dev/vim-herdr-navigation' "$dir/log" || return
}

doom_reruns() {
  local dir="$scratch/doom" core
  prepare_fixture "$dir" || return
  export INSTALL_TEST_STUB_STAGES=0
  core="$HOME/.config/emacs"
  mkdir -p "$core/bin" "$HOME/.config/doom" || return
  printf '; personal config\n' > "$HOME/.config/doom/init.el"
  git -C "$core" init -q || return
  git -C "$core" remote add origin https://github.com/doomemacs/core || return
  cat > "$core/bin/doom" <<'DOOM'
#!/bin/sh
printf 'doom %s\n' "$*" >> "$INSTALL_TEST_LOG"
DOOM
  chmod +x "$core/bin/doom" || return
  "$dir/project/setup" doom > "$dir/output" || return
  "$dir/project/setup" doom > "$dir/output" || return
  printf 'doom install\ndoom install\n' > "$dir/expected"
  cmp -s "$dir/expected" "$dir/log" || return
  rm "$dir/log" || return
  git -C "$core" remote set-url origin https://github.com/unrelated/core || return
  expect_failure "$dir/project/setup" doom || return
  git -C "$core" remote set-url origin https://github.com/doomemacs/core || return
  ln -s "$dir/missing" "$HOME/.emacs.d" || return
  expect_failure "$dir/project/setup" doom || return
  rm "$HOME/.emacs.d" || return
  rm "$core/bin/doom" || return
  expect_failure "$dir/project/setup" doom || return
  [[ ! -e $dir/log ]] || return
}

test_case 'auto detection matches audited product + CPU, rejects unknown/ambiguous/unaudited' detection
test_case 'make install auto-detects and runs every stage sequentially under make -j' sequence
test_case 'auto-detected plan leaves HOME untouched' auto_plan_readonly
test_case 'installer preserves failure status and stops before later stages' stage_failure
test_case 'installer preflight refuses unsafe hosts, selections, conflicts and paths before installs' preflight_refusals
test_case 'Herdr cache reuse, symlink refusal and failed-download cleanup' herdr_cache
test_case 'combined Herdr stage reviews/installs cached script once and preserves reruns' herdr_combined
test_case 'existing local pi/Herdr are preserved without reinstalling' existing_apps
test_case 'Herdr plugin reruns preserve source/preference and reject conflicting IDs' plugin_reruns
test_case 'Doom reruns preserve matching core and refuse unrelated/legacy/incomplete paths' doom_reruns
printf '\n%d installer tests; %d failures\n' "$count" "$failures"
(( failures == 0 ))
