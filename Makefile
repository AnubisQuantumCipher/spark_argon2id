# SPDX-License-Identifier: Apache-2.0
#
# Makefile for spark_argon2id
#
# Provides clean build targets with automatic macOS rpath fixing

.PHONY: all build test kat clean format prove help

# Build mode: debug or release
BUILD_MODE ?= release

# Proof mode: true or false
PROOF ?= false

# Helper script
FIX_RPATH := ./fix_macos_rpath.sh

help:
	@echo "spark_argon2id Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build library and tests (default)"
	@echo "  build    - Build library only"
	@echo "  test     - Build and run smoke test"
	@echo "  kat      - Build and run RFC 9106 KAT tests"
	@echo "  clean    - Remove build artifacts"
	@echo "  format   - Format source code with gnatformat"
	@echo "  prove    - Run SPARK formal verification"
	@echo ""
	@echo "Variables:"
	@echo "  BUILD_MODE={debug|release}  (default: release)"
	@echo "  PROOF={true|false}          (default: false)"

all: build test

build:
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Building spark_argon2id ($(BUILD_MODE) mode)"
	@echo "════════════════════════════════════════════════════════════════"
	alr build -- -XBUILD_MODE=$(BUILD_MODE) -XPROOF=$(PROOF)
	@echo "✅ Build complete"
	@echo ""

test: build
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Building smoke test"
	@echo "════════════════════════════════════════════════════════════════"
	cd tests && alr exec -- gprbuild -P test_spark_argon2id.gpr -XBUILD_MODE=$(BUILD_MODE)
	@$(FIX_RPATH) tests/obj/test_spark_argon2id
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Running smoke test"
	@echo "════════════════════════════════════════════════════════════════"
	cd tests && ./obj/test_spark_argon2id
	@echo "✅ Smoke test passed"
	@echo ""

kat: build
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Building RFC 9106 KAT test harness"
	@echo "════════════════════════════════════════════════════════════════"
	cd tests && alr exec -- gprbuild -P test_rfc9106_kat.gpr -XBUILD_MODE=$(BUILD_MODE)
	@$(FIX_RPATH) tests/obj/test_rfc9106_kat
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Running RFC 9106 Known Answer Tests"
	@echo "════════════════════════════════════════════════════════════════"
	cd tests && ./obj/test_rfc9106_kat
	@echo "✅ KAT tests complete"
	@echo ""

clean:
	@echo "Cleaning build artifacts..."
	rm -rf obj/ alire/
	rm -rf tests/obj/
	rm -rf config/
	@echo "✅ Clean complete"

format:
	@echo "Formatting source code..."
	alr exec -- gnatformat -P spark_argon2id.gpr -U
	@echo "✅ Format complete"

prove:
	@echo "════════════════════════════════════════════════════════════════"
	@echo " Running SPARK formal verification"
	@echo "════════════════════════════════════════════════════════════════"
	alr exec -- gnatprove -P spark_argon2id.gpr -XPROOF=true \
		--level=2 \
		--timeout=60 \
		--steps=0 \
		--counterexamples=on \
		--report=all
	@echo "✅ Proof complete"
	@echo ""
