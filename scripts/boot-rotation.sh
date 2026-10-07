#!/usr/bin/env bash
# Explicit MiniBook boot edit for the inspected archinstall UKI layout.
set -euo pipefail
[[ $EUID == 0 ]] || { printf 'Run make boot-rotation as your normal user.\n' >&2; exit 1; }
menu=/boot/limine.conf
cmd=/etc/kernel/cmdline
uki=/boot/EFI/Linux/arch-linux.efi
for path in "$menu" "$cmd" "$uki" /etc/mkinitcpio.d/linux.preset; do
  [[ -f $path && ! -L $path ]] || { printf 'Refusing unexpected boot layout: %s\n' "$path" >&2; exit 1; }
done
grep -Fq 'arch-linux.efi' "$menu" || { printf 'Limine does not reference the expected UKI.\n' >&2; exit 1; }
grep -Eq '^default_uki="/boot/EFI/Linux/arch-linux.efi"$' /etc/mkinitcpio.d/linux.preset || exit 1
[[ $(wc -l < "$cmd") -le 1 ]] || { printf 'Expected a single-line kernel command line.\n' >&2; exit 1; }
IFS= read -r line < "$cmd" || [[ -n ${line:-} ]]
[[ " $line " == *' root='* ]] || { printf 'Missing root argument; refusing edit.\n' >&2; exit 1; }
read -r -a args <<< "$line"
new=()
for arg in "${args[@]}"; do
  case "$arg" in fbcon=rotate:*|video=DSI-1:panel_orientation=*) ;; *) new+=("$arg");; esac
done
new+=('video=DSI-1:panel_orientation=right_side_up' 'fbcon=rotate:1')
umask 077
backup=$(mktemp -d /var/backups/arch-setup/boot-rotation-XXXXXXXX)
printf 'Backups: %s\n' "$backup"
cp -p -- "$menu" "$backup/limine.conf"
cp -p -- "$cmd" "$backup/cmdline"
cp -p -- "$uki" "$backup/arch-linux.efi"
printf '%s\t%s\n' "$menu" "$backup/limine.conf" "$cmd" "$backup/cmdline" "$uki" "$backup/arch-linux.efi" > "$backup/manifest.tsv"
# Keep entry contents intact; replace only the global menu rotation option.
awk '!/^[[:space:]]*interface_rotation:/' "$menu" > "$backup/menu-body"
{ printf 'interface_rotation: 90\n'; while IFS= read -r row || [[ -n $row ]]; do printf '%s\n' "$row"; done < "$backup/menu-body"; } > "$menu"
printf '%s' "${new[0]}" > "$cmd"
printf ' %s' "${new[@]:1}" >> "$cmd"
printf '\n' >> "$cmd"
printf 'Rebuilding the UKI with the preserved root arguments and rotation settings.\n'
mkinitcpio -p linux
printf 'Boot files updated. Reboot manually to test Limine and console/Ly rotation.\n'
printf 'If rebuilding failed, do not reboot; inspect the backups above.\n'
