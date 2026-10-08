HOST ?= auto
DEV ?= 1
EXTRA ?=
PACKAGE ?=
BOOT_HOOK ?= 0
export HOST DEV EXTRA PACKAGE BOOT_HOOK

.PHONY: ssh install boot-rotation boot-rebuild help bootstrap plan diff packages apply-user apply-system services sources paru aur-plan aur pi herdr herdr-fetch herdr-install herdr-plugins doom shell check boot-check test lint

help:
	@printf '%s\n' 'One-command fresh Arch setup: make install (auto-detects audited hardware; native prompts remain).' 'Read-only: make plan | diff | check | boot-check | aur-plan' 'Advanced stages: packages | paru | aur | sources | apply-user | apply-system | services' 'App stages: pi | herdr | herdr-fetch | herdr-install | herdr-plugins | doom' 'Stages run sequentially under install; failures stop before later stages.' 'No boot changes, shell/account changes, sign-ins, or reboot in make install.' 'make bootstrap shows the plan; it NEVER installs automatically.' 'Defaults: HOST=auto DEV=1. Explicit inspection: make plan HOST=minibook or HOST=t14.' 'Optional: DEV=0 EXTRA=go. PACKAGE=name and BOOT_HOOK=1 are for separate AUR stages only.' 'Private SSH: make ssh SSH_USER=rv (hosts: configs/ssh/hosts.txt; password prompt or SSH_PASSWORD_FILE).' 'Validation: make test | make lint'

bootstrap: plan
	@printf '\nNo changes made. Follow docs/install.md and run reviewed stages explicitly.\n'

install plan diff check boot-check boot-rotation boot-rebuild packages apply-user apply-system services sources paru aur-plan aur pi herdr herdr-fetch herdr-install herdr-plugins doom shell:
	./setup $@

ssh:
	@bash ./scripts/ssh.sh

test:
	./tests/run.sh
	bash ./tests/install.sh
	bash ./tests/ssh.sh

lint:
	./scripts/lint.sh
