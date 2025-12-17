# Sectorc: Trustworthy Bootstrap Compiler Chain
# Top-level Makefile

.PHONY: all clean test bootstrap verify stage0 stage1 stage2 stage3 stage4 stage5

all: stage0 stage1 stage2 stage3 stage4 stage5

# Build individual stages
stage0:
	$(MAKE) -C stage0

stage1:
	$(MAKE) -C stage1

stage2:
	$(MAKE) -C stage2

stage3:
	$(MAKE) -C stage3

stage4:
	$(MAKE) -C stage4

stage5:
	$(MAKE) -C stage5

# Run all tests
test: all
	@echo "=== Running all tests ==="
	@echo ""
	@echo "--- Stage 0 Tests ---"
	@cd tests/stage0 && ./run_tests.sh
	@echo ""
	@echo "--- Stage 1 Tests ---"
	@cd tests/stage1 && ./run_tests.sh
	@echo ""
	@echo "--- Stage 2 Tests ---"
	@cd tests/stage2 && ./run_tests.sh
	@echo ""
	@echo "--- Stage 3 Tests ---"
	@cd tests/stage3 && ./run_tests.sh
	@echo ""
	@echo "--- Stage 4 Tests ---"
	@cd tests/stage4 && ./run_tests.sh
	@echo ""
	@echo "--- Stage 5 Tests ---"
	@cd tests/stage5 && ./run_tests.sh
	@echo ""
	@echo "=== All tests complete ==="

# Full bootstrap from Stage 0
bootstrap: all
	@echo "=== Running full bootstrap ==="
	./bootstrap.sh

# Verify build artifacts
verify:
	@echo "=== Verifying artifacts ==="
	@shasum -a 256 stage0/stage0 stage1/forth stage2/forth stage3/cc stage4/cc stage5/cc 2>/dev/null || true

# Clean all stages
clean:
	$(MAKE) -C stage0 clean
	$(MAKE) -C stage1 clean
	$(MAKE) -C stage2 clean
	$(MAKE) -C stage3 clean
	$(MAKE) -C stage4 clean
	$(MAKE) -C stage5 clean

# Show sizes of all binaries
sizes: all
	@echo "=== Binary sizes ==="
	@ls -la stage0/stage0 stage1/forth stage2/forth stage3/cc stage4/cc stage5/cc 2>/dev/null || true
