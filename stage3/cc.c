/*
 * Stage 3: Subset C Compiler for ARM64 macOS
 *
 * Stage 3 in the bootstrap chain is intended to provide enough C support to
 * compile real programs (types, control flow, expressions, functions).
 *
 * For now, Stage 3 shares the Stage 4 implementation so that the planned
 * Stage 3 feature set is available and buildable from source.
 */

#include "../stage4/cc.c"

