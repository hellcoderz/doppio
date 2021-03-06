# Force the use of bash for shell statements. If we don't do this, many Linux
# variants will use sh.
SHELL := /bin/bash

# Will appear as directories under build/
BUILD_TARGETS = release benchmark dev

# Can be overridden on the command line. This is the name of the tar.gz file
# produced when you run `make dist'.
DIST_NAME = $(shell echo "Doppio_`date +'%y-%m-%d'`.tar.gz")

# DEPENDENCIES
DOPPIO_DIR := $(CURDIR)
COFFEEC  := $(DOPPIO_DIR)/node_modules/coffee-script/bin/coffee
UGLIFYJS := $(DOPPIO_DIR)/node_modules/uglify-js/bin/uglifyjs
OPTIMIST := $(DOPPIO_DIR)/node_modules/optimist/index.js
DOCCO    := $(DOPPIO_DIR)/node_modules/docco/bin/docco
ADMZIP   := $(DOPPIO_DIR)/node_modules/adm-zip/adm-zip.js
JAZZLIB  := $(DOPPIO_DIR)/vendor/classes/java/util/zip/DeflaterEngine.class
JRE      := $(DOPPIO_DIR)/vendor/classes/java/lang/Object.class
SED      := $(shell if command -v gsed >/dev/null; then echo "gsed"; else echo "sed"; fi;)
CPP      := cpp -P -traditional-cpp

# JAVA
SOURCES := $(wildcard classes/test/*.java)
DISASMS := $(SOURCES:.java=.disasm)
RUNOUTS := $(SOURCES:.java=.runout)
CLASSES := $(SOURCES:.java=.class)
# note: TESTS files never get made, but we use them for make rules
TESTS   := $(SOURCES:.java=.test)

DEMO_SRCS    := $(wildcard classes/demo/*.java)
DEMO_CLASSES := $(DEMO_SRCS:.java=.class)
UTIL_SRCS    := $(wildcard classes/util/*.java)
UTIL_CLASSES := $(UTIL_SRCS:.java=.class)
# native stubs for our own implementations
LIB_SRCS     := $(wildcard classes/awt/*.java)
LIB_CLASSES  := $(LIB_SRCS:.java=.class)

# HTML
BROWSER_HTML := $(wildcard browser/[^_]*.html)

# SCRIPTS
# the order here is important: must match the order of includes
# in the browser frontend html.
COMMON_BROWSER_SRCS = vendor/_.js \
	vendor/gLong.js \
	browser/util.coffee \
	browser/node.coffee \
	src/logging.coffee \
	src/exceptions.coffee \
	src/util.coffee \
	src/java_object.coffee \
	src/opcodes.coffee \
	src/attributes.coffee \
	src/ConstantPool.coffee \
	src/disassembler.coffee \
	src/ClassData.coffee \
	src/natives.coffee \
	src/methods.coffee \
	src/runtime.coffee \
	src/ClassLoader.coffee \
	src/jvm.coffee \
	src/testing.coffee \
	browser/untar.coffee
# Release uses the actual jQuery console.
release_BROWSER_SRCS := $(COMMON_BROWSER_SRCS) \
	vendor/jquery.console.js \
	browser/frontend.coffee
dev_BROWSER_SRCS := $(release_BROWSER_SRCS)
# Benchmark uses the mock jQuery console.
benchmark_BROWSER_SRCS := $(COMMON_BROWSER_SRCS) \
	browser/mockconsole.coffee \
	browser/frontend.coffee
# they don't survive uglifyjs and are already minified, so include them
# separately. also, this allows us to put them at the end of the document to
# reduce load time.
ACE_SRCS = vendor/ace/src-min/ace.js \
	vendor/ace/src-min/mode-java.js \
	vendor/ace/src-min/theme-twilight.js
CLI_SRCS := $(wildcard src/*.coffee console/*.coffee)

################################################################################
# TARGETS
################################################################################
# Protect non-file-based targets from not functioning if a file with the
# target's name is present.
.PHONY: release benchmark dist dependencies java test clean docs build dev

# Builds a release or benchmark version of Doppio without the documentation.
# This is a static pattern rule. '%' gets substituted for the target name.
release benchmark: %: dependencies build/% build/%/browser \
	$(patsubst %,build/\%/%,$(notdir $(BROWSER_HTML))) build/%/favicon.ico \
	build/%/compressed.js build/%/browser/mini-rt.tar build/%/ace.js \
	build/%/browser/style.css $(DEMO_CLASSES) $(UTIL_CLASSES) \
	build/%/classes build/%/vendor
	rsync browser/*.svg browser/*.png build/$*/browser/
	cd build/$*; $(COFFEEC) $(DOPPIO_DIR)/tools/gen_dir_listings.coffee > browser/listings.json

# dev: unoptimized build
dev: dependencies build/dev build/dev/browser \
	$(patsubst %.coffee,build/dev/%.js,$(filter %.coffee,$(dev_BROWSER_SRCS))) \
	build/dev/browser/style.css build/dev/index.html build/dev/favicon.ico $(DEMO_CLASSES) \
	build/dev/browser/mini-rt.tar build/dev/classes build/dev/vendor
	rsync $(filter %.js,$(dev_BROWSER_SRCS)) build/dev/vendor
	rsync browser/*.svg browser/*.png build/dev/browser/
	cd build/dev; $(COFFEEC) $(DOPPIO_DIR)/tools/gen_dir_listings.coffee > browser/listings.json

release-cli: $(CLI_SRCS:%.coffee=build/release/%.js) \
	build/release/classes build/release/vendor doppio

dev-cli: $(CLI_SRCS:%.coffee=build/dev/%.js) \
	build/dev/classes build/dev/vendor doppio-dev

# Builds a distributable version of Doppio.
dist: $(DIST_NAME)
$(DIST_NAME): release docs
	tar czf $(DIST_NAME) build/release

# Installs or checks for any required dependencies.
dependencies: $(COFFEEC) $(UGLIFYJS) $(OPTIMIST) $(JAZZLIB) $(JRE) $(DOCCO) $(ADMZIP)
	@git submodule update --quiet --init --recursive
	@rm -f classes/test/failures.txt
$(COFFEEC):
	npm install coffee-script@1.3.3
$(UGLIFYJS):
	npm install uglify-js@1
$(OPTIMIST):
	npm install optimist
$(DOCCO):
	npm install docco
$(ADMZIP):
	npm install adm-zip
$(JAZZLIB):
	$(error JazzLib not found. Unzip it to vendor/classes/, or run ./tools/setup.sh.)
$(JRE):
	$(error Java class library not found. Unzip it to vendor/classes/, or run ./tools/setup.sh.)

# Used to test the chosen Java compiler in setup.sh.
java: $(CLASSES) $(DISASMS) $(RUNOUTS) $(DEMO_CLASSES) $(UTIL_CLASSES) $(LIB_CLASSES)

# Runs the Java tests in classes/test with the node runner.
test: dependencies $(TESTS)
	@echo ''
	@cat classes/test/failures.txt
# compiling each one by itself is really inefficient...
%.class: %.java
	javac $^
# phony *.test targets allow us to test with -j4 parallelism
classes/test/%.test: release-cli classes/test/%.class classes/test/%.disasm classes/test/%.runout
	@node build/release/console/test_runner.js classes/test/$* --makefile
classes/test/%.disasm: classes/test/%.class
	javap -c -verbose -private classes/test/$* >classes/test/$*.disasm
# some tests may throw exceptions. The '-' flag tells make to carry on anyway.
classes/test/%.runout: classes/test/%.class
	-java classes/test/$* &>classes/test/$*.runout

clean:
	@rm -f tools/*.js tools/preload browser/listings.json doppio doppio-dev
	@rm -rf build/*
	@rm -f $(patsubst %.md,%.html,$(wildcard browser/*.md))

distclean: clean
	@rm -f $(CLASSES) $(DISASMS) $(RUNOUTS) $(DEMO_CLASSES)

# docs need to be generated in one shot so docco can create the full jumplist.
# This is slow, so we have it as a separate target (even though it is needed
# for a full release build).
docs: dependencies build/release
	$(DOCCO) $(filter %.coffee, $(release_BROWSER_SRCS))
	rm -rf build/release/docs
	mv docs build/release

tools/preload: release-cli
	@if [ -z "$$KEEP_PRELOAD" ]; then \
		echo "Generating list of files to preload in browser... (will take a few seconds)"; \
		node build/release/console/runner.js classes/util/Javac ./classes/test/FileOps.java --list-class-cache > tools/preload; \
	else \
		echo "Not regenerating tools/preload because you told me so"; \
	fi

################################################################################
# BUILD DIRECTORY TARGETS
################################################################################

# subst: Use 'manual' substitution because we don't want this to be a pattern
# rule.  there are multiple targets that need to be individually fulfilled, but
# pattern rules assume they are all fulfilled in one shot.
BUILD_FOLDERS = build/% build/%/browser build/%/console build/%/src
$(foreach TARGET,$(BUILD_TARGETS),$(subst %,$(TARGET),$(BUILD_FOLDERS))):
	mkdir -p $@

browser/_about.html: browser/_about.md
	rdiscount $? > $@
build/release/about.html build/benchmark/about.html: browser/_about.html

build/dev/%.html: browser/%.html $(wildcard browser/_*.html)
	$(CPP) $< $@

build/release/%.html build/benchmark/%.html: browser/%.html $(wildcard browser/_*.html)
	$(CPP) -DRELEASE $< $@

build/%/favicon.ico: browser/favicon.ico
	rsync $< $@

build/%/ace.js: $(ACE_SRCS)
	for src in $(ACE_SRCS); do \
		cat $${src}; \
		echo ";"; \
	done > $@

# The | prevents the prerequisite from being included in $^, and avoids
# re-executing the rule when the folder is 'updated' with `mkdir -p`.
build/%/browser/style.css: vendor/bootstrap/css/bootstrap.min.css \
	browser/style.css | build/%/browser
	cat $^ > $@

# Prevent this from being treated as pattern rule (because it has multiple targets)
$(foreach TARGET,$(BUILD_TARGETS),$(subst %,$(TARGET),build/%/classes build/%/vendor)):
	ln -sfn $(DOPPIO_DIR)/$(notdir $@) $@

build/%/browser/mini-rt.tar: tools/preload
	COPYFILE_DISABLE=true && tar -c -T tools/preload -f $@

doppio doppio-dev:
	echo "node \`dirname \$$0\`/build/$(if $(findstring dev,$@),dev,release)/console/runner.js \$$@" > $@
	chmod +x $@

# Never delete these files in the event of a failure.
.SECONDARY: $(CLASSES) $(DISASMS) $(RUNOUTS) $(DEMO_CLASSES) $(UTIL_CLASSES)

# SECONDEXPANSION allows us to use '%' and '$@' in our prerequisites. These
# variables are not bound when the first expansion occurs. The directive
# applies to all rules from this point on, so put it at the bottom of the file.
.SECONDEXPANSION:
build/release/compressed.js build/benchmark/compressed.js: build/%/compressed.js:\
	build/% $$(%_BROWSER_SRCS)
	for src in $($*_BROWSER_SRCS); do \
		if [ "$${src##*.}" == "coffee" ]; then \
			$(: `` is essentially Coffeescript's equivalent of Python's 'pass') \
			$(SED) -r "s/^( *)(debug|v?trace).*$$/\1\`\`/" $${src} | $(COFFEEC) --stdio --print; \
		else \
			cat $${src}; \
		fi; \
		echo ";"; \
	done | $(UGLIFYJS) --define RELEASE --define UNSAFE --no-mangle --unsafe > $@

build/dev/%.js: %.coffee | $$(dir $$@)
	$(COFFEEC) --print -c $< > $@

build/release/%.js build/benchmark/%.js: %.coffee | $$(dir $$@)
	$(SED) -r "s/^( *)(debug|v?trace).*$$/\1\`\`/" $< | $(COFFEEC) --stdio --print > $@
	$(UGLIFYJS) --define RELEASE --define UNSAFE --no-mangle --unsafe --beautify --overwrite $@
