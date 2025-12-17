/*
 * Stage 0: Hex Loader for ARM64 macOS
 *
 * Reads ASCII hex pairs from stdin, writes to executable buffer, jumps to it.
 * Target: Minimal, auditable code for trustworthy bootstrapping.
 *
 * This C version uses macOS JIT APIs for Apple Silicon compatibility.
 * The generated assembly should be inspected for verification.
 *
 * Compile: clang -O0 -o stage0 stage0.c
 * Size target: ~512 bytes of actual logic
 */

#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>

/* Buffer size for loaded code */
#define BUFSIZE 0x10000  /* 64KB */

/* Convert hex character to nibble value (0-15) */
static int hex_to_nibble(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;  /* Invalid hex digit */
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
    unsigned char *buf, *ptr;
    int c, hi, lo;
    void (*code)(void);

    /* Allocate executable memory with MAP_JIT for Apple Silicon */
    buf = mmap(0, BUFSIZE,
               PROT_READ | PROT_WRITE | PROT_EXEC,
               MAP_PRIVATE | MAP_ANON | MAP_JIT,
               -1, 0);

    if (buf == MAP_FAILED) {
        write(2, "mmap failed\n", 12);
        return 1;
    }

    ptr = buf;

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

        /* Convert first hex digit */
        hi = hex_to_nibble(c);
        if (hi < 0) continue;  /* Skip invalid characters */

        /* Read and convert second hex digit */
        c = read_byte();
        if (c == -1) break;
        lo = hex_to_nibble(c);
        if (lo < 0) continue;

        /* Store byte and advance pointer */
        *ptr++ = (hi << 4) | lo;
    }

    /* Disable write access, enable execute */
    pthread_jit_write_protect_np(1);

    /* Flush instruction cache for JIT region */
    sys_icache_invalidate(buf, ptr - buf);

    /* Jump to loaded code */
    code = (void (*)(void))buf;
    code();

    return 0;
}
