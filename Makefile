TESTS_INIT=tests/minimal_init.lua
TESTS_DIR=tests/

.PHONY: test

test_nvim:
	@nvim \
		--headless \
		--noplugin \
		-u ${TESTS_INIT} \
		-c "PlenaryBustedDirectory ${TESTS_DIR} { minimal_init = '${TESTS_INIT}' }"

test:
	-$(MAKE) test_nvim || exit 1
