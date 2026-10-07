HOST ?= minibook
DEV ?= 1
EXTRA ?=
PACKAGE ?=
BOOT_HOOK ?= 0
export HOST DEV EXTRA PACKAGE BOOT_HOOK

.PHONY: boot-rotation boot-rebuild help bootstrap plan diff packages apply-user apply-system services sources paru aur-plan aur pi herdr-fetch herdr-install herdr-plugins doom shell check boot-check test lint

help:
	@printf '%s\n' 'Read-only: make plan | diff | check | boot-check | aur-plan' 'Fresh Arch stages: packages | paru | aur | sources | apply-user | apply-system | services' 'Targets run directly; package managers and external installers retain their own prompts.' 'AUR packages: make paru bootstraps the helper; make aur uses Paru with build-script review; optional PACKAGE=name selects one declared package.' 'Separate installs: pi | herdr-fetch | herdr-install | herdr-plugins | doom' 'make bootstrap shows the plan; it NEVER installs automatically.' 'Defaults: HOST=minibook DEV=1. Optional: DEV=0 EXTRA=go BOOT_HOOK=1.' 'Validation: make test | make lint'

bootstrap: plan
	@printf '\nNo changes made. Follow docs/install.md and run reviewed stages explicitly.\n'

plan diff check boot-check boot-rotation boot-rebuild packages apply-user apply-system services sources paru aur-plan aur pi herdr-fetch herdr-install herdr-plugins doom shell:
	./setup $@

test:
	./tests/run.sh

lint:
	./scripts/lint.sh
