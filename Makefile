DISTRO := $(shell if [ "$(shell uname -s)" = "Darwin" ]; then echo "darwin"; elif [ -f /etc/os-release ]; then . /etc/os-release && echo $$ID; else echo "unknown"; fi)
-include mk/$(DISTRO).mk

CFLAGS_COMMON = -std=c17 -pedantic \
  -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wwrite-strings \
  -Werror -Wall -Wextra -Wformat=2 -Wconversion -Wcast-qual -Wundef \
  -Wdate-time -Winit-self -Wstrict-overflow=2 \
  -MMD -MP -fstack-protector-strong -fPIC \
  -Wimplicit-fallthrough -Walloca -Wvla \
  -Wnull-dereference -Wdouble-promotion

CFLAGS_DEBUG = -D_FORTIFY_SOURCE=2 -g -O0

CFLAGS_RELEASE_OPTS = -DNDEBUG -g -O3 -ffunction-sections

CFLAGS_BASE = $(CFLAGS_COMMON) $(CFLAGS_DEBUG)
CFLAGS_RELEASE = $(CFLAGS_COMMON) $(CFLAGS_RELEASE_OPTS)

CFLAGS_TEST = $(filter-out -Wmissing-prototypes,$(CFLAGS_COMMON)) $(CFLAGS_DEBUG) $(DISTRO_CFLAGS)

CFLAGS = $(CFLAGS_BASE) $(DISTRO_CFLAGS)

LDFLAGS = $(DISTRO_LDFLAGS)

PREFIX ?= $(HOME)/.local

SRCDIR := src
OBJDIR := obj
BINDIR := bin
REPORTSDIR := reports
TMPDIR := tmp

SOURCES := $(wildcard $(SRCDIR)/*.c)
OBJECTS := $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
DEPS := $(OBJECTS:.o=.d)

EXECUTABLE := $(BINDIR)/myapp

all: $(EXECUTABLE)

release: CFLAGS = $(CFLAGS_RELEASE) $(DISTRO_CFLAGS)
release: clean $(EXECUTABLE)

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(BINDIR):
	mkdir -p $(BINDIR)

$(OBJDIR)/%.o: $(SRCDIR)/%.c | $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(EXECUTABLE): $(OBJECTS) | $(BINDIR)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@

clean:
	rm -rf $(OBJDIR) $(BINDIR) $(REPORTSDIR) $(TMPDIR) tags

-include $(DEPS)

.PHONY: all release clean check install uninstall tags fmt help deps run coverage sanitize analyze check-all

check:
	@mkdir -p $(TMPDIR)
	@echo "Running tests..."
	@for test in tests/*_test.c; do \
		echo ""; \
		testname=$$(basename $$test .c); \
		libname=$${testname%_test}; \
		echo "testing $$libname..."; \
		$(CC) $(CFLAGS_TEST) -I./src $$test src/$$libname.c $(LDFLAGS) -MF $(TMPDIR)/$$testname.d -o $(TMPDIR)/$$testname; \
		$(TMPDIR)/$$testname || exit 1; \
	done
	@echo ""

install: $(EXECUTABLE)
	@mkdir -p $(PREFIX)/bin
	install -m 755 $(EXECUTABLE) $(PREFIX)/bin/
	@echo "Installed executable to $(PREFIX)/bin/myapp"

uninstall:
	rm -f $(PREFIX)/bin/myapp
	@echo "Removed $(PREFIX)/bin/myapp"

tags:
	@command -v ctags >/dev/null 2>&1 || { \
		echo "Error: ctags is not installed."; \
		exit 1; \
	}
	ctags -R $(SRCDIR)

run: $(EXECUTABLE)
	$(EXECUTABLE)

fmt:
	@find $(SRCDIR) tests \( -name "*.c" -o -name "*.h" \) -type f \
		| while read file; do \
			echo "Formatting: $$file"; \
			clang-format -i "$$file"; \
		done

help:
	@echo "Available targets:"
	@echo "  all       - Build the project (default, debug mode)"
	@echo "  release   - Build optimized release version"
	@echo "  run       - Build and run the executable"
	@echo "  clean     - Remove build artifacts"
	@echo "  deps      - Show package installation instructions"
	@echo "  install   - Install the program"
	@echo "  uninstall - Uninstall the program"
	@echo "  check     - Run tests"
	@echo "  coverage  - Run tests with coverage analysis"
	@echo "  sanitize  - Run tests with AddressSanitizer and UBSan"
	@echo "  analyze   - Run static analysis (clang or cppcheck)"
	@echo "  check-all - Run comprehensive checks (check + analyze + sanitize + coverage)"
	@echo "  tags      - Generate ctags file"
	@echo "  fmt       - Format code with clang-format"
	@echo "  help      - Show this help message"

deps:
	@echo ""
	@echo "To install required development packages."
	@echo ""
	@echo "  $(INSTALL_DEPS_CMD)"
	@echo ""

coverage: require-glib
	@mkdir -p $(REPORTSDIR) $(TMPDIR)
	@echo "Running tests with coverage..."
	@for test in tests/*_test.c; do \
		testname=$$(basename $$test .c); \
		libname=$${testname%_test}; \
		echo "Testing $$libname with coverage..."; \
		$(CC) $(CFLAGS_TEST) -I./src $$test src/$$libname.c $(LDFLAGS) --coverage -MF $(TMPDIR)/$$testname.d -o $(TMPDIR)/$$testname; \
		$(TMPDIR)/$$testname || exit 1; \
	done
	@echo "Generating coverage report..."
	@for file in src/*.c tests/*.c; do \
		base=$$(basename $$file .c); \
		for testfile in $(TMPDIR)/*_test-$${base}.gcda $(TMPDIR)/$${base}.gcda; do \
			if [ -f "$$testfile" ]; then \
				cd $(TMPDIR) && gcov "$$(basename $$testfile)"; \
			fi; \
		done; \
	done
	@mv $(TMPDIR)/*.gcov $(REPORTSDIR)/ 2>/dev/null || true
	@echo "Coverage files: $(REPORTSDIR)/*.gcov (only our source code)"

sanitize: CFLAGS = $(filter-out -D_FORTIFY_SOURCE=2,$(CFLAGS_COMMON) $(CFLAGS_DEBUG)) $(DISTRO_CFLAGS) -fsanitize=address,undefined
sanitize: LDFLAGS = $(DISTRO_LDFLAGS) -fsanitize=address,undefined
sanitize: require-glib clean
	@mkdir -p $(TMPDIR)
	@echo "Running tests with sanitizers..."
	@for test in tests/*_test.c; do \
		testname=$$(basename $$test .c); \
		libname=$${testname%_test}; \
		echo "Testing $$libname with sanitizers..."; \
		$(CC) $(filter-out -D_FORTIFY_SOURCE=2,$(CFLAGS_TEST)) -I./src $$test src/$$libname.c $(LDFLAGS) -fsanitize=address,undefined -MF $(TMPDIR)/$$testname.d -o $(TMPDIR)/$$testname; \
		$(TMPDIR)/$$testname || exit 1; \
	done

analyze:
	@echo "Running static analysis..."
	@mkdir -p $(REPORTSDIR) $(TMPDIR)
	@command -v clang >/dev/null 2>&1 && { \
		echo "Using clang static analyzer..."; \
		if clang --analyze $(filter-out -MMD -MP -fanalyzer,$(CFLAGS)) src/*.c tests/*.c; then \
			echo "Static analysis completed - no issues found!"; \
		fi; \
		mv *.plist $(REPORTSDIR)/ 2>/dev/null || true; \
	} || { \
		echo "clang not found, trying cppcheck..."; \
		command -v cppcheck >/dev/null 2>&1 && { \
			cppcheck --enable=all --std=c17 --suppress=missingIncludeSystem --suppress=missingInclude src/ --quiet && \
			echo "Static analysis completed - no issues found!"; \
		} || { \
			echo "No static analysis tools found. Install clang or cppcheck."; \
		}; \
	}

check-all:
	@echo "=== Running comprehensive checks ==="
	@echo "1/4: Running unit tests..."
	@$(MAKE) check
	@echo ""
	@echo "2/4: Running static analysis..."
	@$(MAKE) analyze
	@echo ""
	@echo "3/4: Running sanitizer tests..."
	@$(MAKE) sanitize
	@echo ""
	@echo "4/4: Running coverage analysis..."
	@$(MAKE) coverage
	@echo ""
	@echo "=== All checks completed successfully! ==="
