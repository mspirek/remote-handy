SWIFT_ENV = CLANG_MODULE_CACHE_PATH="$(CURDIR)/.module-cache"

.PHONY: test-fixtures build-menubar-app build-donor-app setup-local-signing install-local privacy-scan

test-fixtures:
	$(SWIFT_ENV) swift run remote-handy-fixture-tests

build-donor-app:
	./scripts/build-copy-donor-app.zsh

build-menubar-app: build-donor-app
	./scripts/build-menubar-app.zsh

setup-local-signing:
	./scripts/setup-local-signing.zsh

install-local:
	./scripts/install-local.zsh

privacy-scan:
	./scripts/privacy-scan.zsh
