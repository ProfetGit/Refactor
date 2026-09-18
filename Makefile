LUA ?= lua5.1
RUN = sh Tools/dev-env.sh

.PHONY: check lint test api-check api-index package dev-setup
# Checkout the API index is generated from: git clone --branch live https://github.com/Gethe/wow-ui-source
SOURCE ?= $(HOME)/wow-ui-source
check: lint test api-check

lint:
	$(RUN) luacheck Core UI Modules Modules_LoD Integrations Locales Media Libs/LibRefactorTheme-1.0 Libs/LibRefactorPrice-1.0 Tools Tests
	$(RUN) $(LUA) Tools/lint.lua

test:
	$(RUN) busted --lua=$(LUA) Tests/spec

api-check:
	$(RUN) $(LUA) Tools/api-check.lua

package: check
	python3 Tools/package.py

api-index:
	python3 Tools/source-index.py "$(SOURCE)"

dev-setup:
	luarocks --lua-version=5.1 --tree=.tools install busted
	luarocks --lua-version=5.1 --tree=.tools install luacheck
	luarocks --lua-version=5.1 --tree=.tools install dkjson
