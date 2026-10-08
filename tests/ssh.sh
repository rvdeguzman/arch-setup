#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export HOME=$temp/home
mkdir -p "$HOME/.ssh" "$temp/bin"
printf 'Host other\n    User original\n' > "$HOME/.ssh/config"
printf '# original bashrc\n' > "$HOME/.bashrc"
printf 'fixture-password\n' > "$temp/password"
export SSH_USER=fixture SSH_PASSWORD_FILE=$temp/password
bash "$ROOT/scripts/ssh.sh" > "$temp/output"
grep -q 'original' "$HOME/.ssh/config"
[[ $(stat -c %a "$HOME/.ssh/arch-setup/password") == 600 ]]
[[ $(stat -c %a "$HOME/.ssh/arch-setup/askpass") == 700 ]]
[[ $(ssh -F "$HOME/.ssh/arch-setup/config" -G komagome 2>/dev/null | awk '$1 == "user" {print $2}') == fixture ]]
bash "$ROOT/scripts/ssh.sh" > "$temp/output"
[[ $(grep -c '^Include ~/.ssh/arch-setup/config$' "$HOME/.ssh/config") == 1 ]]
[[ $(grep -c '^\[ ! -r' "$HOME/.bashrc") == 1 ]]
[[ $(find "$HOME/.ssh/arch-setup" -path '*/.ssh/config' -type f | wc -l) == 2 ]]
[[ $(ARCH_SETUP_SSH_LOGIN=fixture@komagome "$HOME/.ssh/arch-setup/askpass" "fixture@komagome's password:") == fixture-password ]]
# Mock the client: selected destinations get the helper, others do not.
# shellcheck disable=SC2016 # Literal script for the mock client.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ ${1-} == -G ]]; then printf "user fixture\n"; else printf "%s|%s\n" "${SSH_ASKPASS_REQUIRE-unset}" "${ARCH_SETUP_SSH_LOGIN-unset}"; fi' > "$temp/bin/ssh"
chmod +x "$temp/bin/ssh"
export PATH="$temp/bin:$PATH"
unset SSH_ASKPASS_REQUIRE ARCH_SETUP_SSH_LOGIN
# shellcheck source=/dev/null
source "$HOME/.ssh/arch-setup/shell.sh"
[[ $(ssh komagome) == 'force|fixture@komagome' ]]
[[ $(ssh elsewhere) == 'unset|unset' ]]
[[ $(ssh -v komagome) == 'unset|unset' ]]
# Validate inputs before touching an existing password/config.
printf 'bad *\n' > "$temp/hosts"
export SSH_HOSTS_FILE=$temp/hosts
if bash "$ROOT/scripts/ssh.sh" > "$temp/output" 2>&1; then exit 1; fi
[[ $(< "$HOME/.ssh/arch-setup/password") == fixture-password ]]
unset SSH_HOSTS_FILE
rm "$HOME/.zshrc"
ln -s "$temp/victim" "$HOME/.zshrc"
if bash "$ROOT/scripts/ssh.sh" > "$temp/output" 2>&1; then exit 1; fi
[[ ! -e $temp/victim ]]
printf 'SSH setup tests passed (fixtures only, no connections).\n'
