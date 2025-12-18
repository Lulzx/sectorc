/*
 * Stage 0: Hex Loader for ARM64 macOS
 *
 * Reads ASCII hex pairs from stdin, writes to executable buffer, jumps to it.
 * Target: Minimal, auditable code for trustworthy bootstrapping.
 *
 * This version uses MAP_JIT and pthread_jit_write_protect_np() to safely
 * write to executable memory on Apple Silicon (W^X enforcement).
 *
 * Compile: clang -O0 -o stage0 stage0.c
 */

#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>

/* Buffer sizes */
#define CODE_SIZE 0x4000   /* 16KB for code */

/* Convert hex character to nibble value (0-15) */
static int hex_to_nibble(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

/* Read one byte from stdin, returns -1 on EOF */
static int read_byte(void) {
    unsigned char c;
    if (read(0, &c, 1) <= 0) return -1;
    return c;
}

/* Skip to end of line (for comments) */
static void skip_line(void) {
    int c;
    while ((c = read_byte()) != -1 && c != '\n')
        ;
}

int main(void) {
    unsigned char *code_buf, *ptr;
    int c, hi, lo;
    void (*code)(void *data);

    /* Allocate executable memory for code (will be RX after switching) */
    code_buf = mmap(0, CODE_SIZE,
                    PROT_READ | PROT_WRITE | PROT_EXEC,
                    MAP_PRIVATE | MAP_ANON | MAP_JIT,
                    -1, 0);

    if (code_buf == MAP_FAILED) {
        write(2, "code mmap failed\n", 17);
        return 1;
    }

    ptr = code_buf;

    /* Enable write access to JIT memory */
    pthread_jit_write_protect_np(0);

    /* Main loop: read hex pairs from stdin */
    while ((c = read_byte()) != -1) {
        /* Skip whitespace */
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
            continue;

        /* Skip comments (lines starting with ; or #) */
        if (c == ';' || c == '#') {
            skip_line();
            continue;
        }

        /* Backtick '`' triggers execution */
        if (c == '`') break;

        /* Convert first hex digit */
        hi = hex_to_nibble(c);
        if (hi < 0) continue;

        /* Read and convert second hex digit */
        c = read_byte();
        if (c == -1) break;
        lo = hex_to_nibble(c);
        if (lo < 0) continue;

        /* Store byte and advance pointer */
        if (ptr - code_buf >= CODE_SIZE) {
            write(2, "Code overflow\n", 14);
            return 1;
        }
        *ptr++ = (hi << 4) | lo;
    }

    /* Switch to execute mode - code is now RX (no more writes allowed) */
    pthread_jit_write_protect_np(1);

    /* Flush instruction cache */
    sys_icache_invalidate(code_buf, ptr - code_buf);

    /* Jump to loaded code (Stage 1 will allocate its own data buffer) */
    code = (void (*)(void *))code_buf;
    code(0);

    return 0;
}
