#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
user=${SSH_USER:-$(id -un)}
hosts_file=${SSH_HOSTS_FILE:-$ROOT/configs/ssh/hosts.txt}
[[ $user =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]] || { printf 'Invalid SSH_USER\n' >&2; exit 1; }
[[ -f $hosts_file ]] || { printf 'Missing SSH_HOSTS_FILE\n' >&2; exit 1; }
hosts=()
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    read -r -a fields <<< "$line"
    ((${#fields[@]})) || continue
    [[ ${#fields[@]} == 1 && ${fields[0]} =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || {
        printf 'Hosts must be literal names/IP addresses, one per line\n' >&2; exit 1;
    }
    hosts+=("${fields[0]}")
done < "$hosts_file"
((${#hosts[@]})) || { printf 'Empty hosts list\n' >&2; exit 1; }

# Preflight all destinations before modifying anything. Never follow symlinks.
private=$HOME/.ssh/arch-setup
for dir in "$HOME" "$HOME/.ssh" "$private"; do
    [[ ! -L $dir && ( ! -e $dir || -d $dir ) ]] || { printf 'Unsafe directory: %s\n' "$dir" >&2; exit 1; }
done
for file in "$HOME/.ssh/config" "$HOME/.bashrc" "$HOME/.zshrc" \
    "$private/password" "$private/hosts" "$private/config" "$private/askpass" "$private/shell.sh"; do
    [[ ! -L $file && ( ! -e $file || -f $file ) ]] || { printf 'Unsafe file: %s\n' "$file" >&2; exit 1; }
done
if [[ -n ${SSH_PASSWORD_FILE:-} ]]; then
    mapfile -t passwords < "$SSH_PASSWORD_FILE"
    [[ ${#passwords[@]} == 1 && -n ${passwords[0]} ]] || { printf 'Password file must contain one nonempty line\n' >&2; exit 1; }
    password=${passwords[0]}
    unset passwords
else
    IFS= read -r -s -p 'SSH password (saved locally, not in Git): ' password < /dev/tty
    printf '\n' > /dev/tty
    [[ -n $password ]] || { printf 'Empty password refused\n' >&2; exit 1; }
fi
umask 077
mkdir -p -- "$private"
chmod 700 "$HOME/.ssh" "$private"
backup=$(mktemp -d "$private/backup.XXXXXXXX")
for file in "$HOME/.ssh/config" "$HOME/.bashrc" "$HOME/.zshrc" \
    "$private/password" "$private/hosts" "$private/config" "$private/askpass" "$private/shell.sh"; do
    if [[ -e $file ]]; then
        name=${file#"$HOME/"}
        mkdir -p -- "$backup/$(dirname -- "$name")"
        cp -p -- "$file" "$backup/$name"
    fi
done
printf '%s\n' "$password" > "$private/password"
unset password
printf '%s\n' "${hosts[@]}" > "$private/hosts"
{
    printf 'Host'
    printf ' %s' "${hosts[@]}"
    printf '\n    User %s\n    StrictHostKeyChecking ask\n' "$user"
} > "$private/config"
cp -- "$ROOT/scripts/ssh-askpass.sh" "$private/askpass"
cp -- "$ROOT/scripts/ssh-shell.sh" "$private/shell.sh"
chmod 600 "$private/password" "$private/hosts" "$private/config" "$private/shell.sh"
chmod 700 "$private/askpass"
include='Include ~/.ssh/arch-setup/config'
# An Include at the beginning stays outside any existing Host/Match block.
if ! grep -qxF "$include" "$HOME/.ssh/config" 2>/dev/null; then
    temp=$(mktemp "$private/config.XXXXXXXX")
    printf '%s\n' "$include" > "$temp"
    if [[ -f $HOME/.ssh/config ]]; then
        # A trailing newline is harmless; preserve all original content.
        while IFS= read -r line || [[ -n $line ]]; do printf '%s\n' "$line"; done < "$HOME/.ssh/config" >> "$temp"
    fi
    mv -- "$temp" "$HOME/.ssh/config"
fi
# shellcheck disable=SC2016 # Expanded when the generated startup line is sourced.
source_line='[ ! -r "$HOME/.ssh/arch-setup/shell.sh" ] || . "$HOME/.ssh/arch-setup/shell.sh"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if ! grep -qxF "$source_line" "$rc" 2>/dev/null; then
        printf '\n# Private SSH password helper for the explicitly listed hosts.\n%s\n' "$source_line" >> "$rc"
    fi
done
printf 'SSH configured for: %s\n' "${hosts[*]}"
printf 'Backups: %s\nOpen a new terminal or run: source ~/.ssh/arch-setup/shell.sh\n' "$backup"
printf 'Use host-first calls: ssh komagome (options before the host use normal SSH prompts).\n'
