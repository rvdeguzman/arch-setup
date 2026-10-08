#!/usr/bin/env bash
set -euo pipefail

# Talk to the daemon directly; no powerprofilesctl/Python dependency.
service=net.hadess.PowerProfiles
object=/net/hadess/PowerProfiles
interface=net.hadess.PowerProfiles
current=$(busctl --system get-property "$service" "$object" "$interface" ActiveProfile)
current=${current#s \"}
current=${current%\"}

profiles=(power-saver balanced performance)
labels=('Power saver' 'Balanced' 'Performance')
for i in "${!profiles[@]}"; do
  if [[ ${profiles[i]} == "$current" ]]; then
    labels[i]="> ${labels[i]}"
  fi
done

# Canceling the menu must not change the profile.
if ! choice=$(printf '%s\n' "${labels[@]}" | fuzzel --dmenu --index --lines=3 --width=28 --prompt='Power plan: '); then
  exit 0
fi
case "$choice" in
  0|1|2) profile=${profiles[choice]} ;;
  *) exit 0 ;;
esac
[[ $profile != "$current" ]] || exit 0
busctl --system set-property "$service" "$object" "$interface" ActiveProfile s "$profile"
