#!/usr/bin/env bash
set -euo pipefail
# Only answer the selected host's password prompt, never host-key/MFA prompts.
case "${1-}" in
  "${ARCH_SETUP_SSH_LOGIN:?}'s password:"*)
    IFS= read -r password < "$HOME/.ssh/arch-setup/password" || [[ -n ${password-} ]]
    printf '%s\n' "$password"
    ;;
  *)
    if [[ -r /dev/tty ]]; then
      printf '%s ' "${1-}" > /dev/tty
      IFS= read -r answer < /dev/tty
      printf '%s\n' "$answer"
    else
      exit 1
    fi
    ;;
esac
