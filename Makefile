HOST ?= minibook
DEV ?= 1
EXTRA ?=
PACKAGE ?=
BOOT_HOOK ?= 0
export HOST DEV EXTRA PACKAGE BOOT_HOOK

.PHONY: help bootstrap plan diff packages apply-user apply-system services sources aur-plan aur-fetch aur-review aur-install pi herdr-fetch herdr-install herdr-plugins doom shell check boot-check test lint

help:
	@printf '%s\n' 'Read-only: make plan | diff | check | boot-check | aur-plan' 'Fresh Arch only, confirmation required: packages | sources | apply-user | apply-system | services' 'Separate installs: aur-fetch/aur-review/aur-install PACKAGE=name | pi | herdr-fetch | herdr-install | herdr-plugins | doom' 'make bootstrap shows the plan; it NEVER installs automatically.' 'Defaults: HOST=minibook DEV=1. Optional: DEV=0 EXTRA=go BOOT_HOOK=1.' 'Validation: make test | make lint'

bootstrap: plan
	@printf '\nNo changes made. Follow docs/install.md and run reviewed stages explicitly.\n'

plan diff check boot-check packages apply-user apply-system services sources aur-plan aur-fetch aur-review aur-install pi herdr-fetch herdr-install herdr-plugins doom shell:
	./setup $@

test:
	./tests/run.sh

lint:
	./scripts/lint.sh
