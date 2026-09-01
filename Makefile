DEPS := .deps

.PHONY: test lint deps clean

test: deps
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

lint:
	stylua --check lua plugin tests scripts

deps: $(DEPS)/mini.nvim $(DEPS)/sqlite.lua

$(DEPS)/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

$(DEPS)/sqlite.lua:
	git clone --filter=blob:none --depth 1 https://github.com/kkharji/sqlite.lua $@

clean:
	rm -rf $(DEPS)
