# Sourced by Bash/Zsh. Only host-first calls use the saved password.
ssh() {
    local destination="${1-}" host login configured matched=0
    host="${destination##*@}"
    while IFS= read -r configured; do
        if [[ "$host" == "$configured" ]]; then
            matched=1
            break
        fi
    done < "$HOME/.ssh/arch-setup/hosts"
    if [[ $matched == 1 ]]; then
        login="$(command ssh -G "$@" 2>/dev/null | awk '$1 == "user" {print $2}')" || return
        SSH_ASKPASS="$HOME/.ssh/arch-setup/askpass" \
            SSH_ASKPASS_REQUIRE=force ARCH_SETUP_SSH_LOGIN="$login@$host" \
            command ssh "$@"
    else
        command ssh "$@"
    fi
}
