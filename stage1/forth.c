/*
 * Stage 1: Minimal Forth Interpreter
 *
 * A simple, auditable Forth implementation for the bootstrap chain.
 * Implements ~20 core primitives plus the outer interpreter.
 *
 * Size target: ~2KB of essential logic
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>

/* Stack sizes */
#define STACK_SIZE     256
#define RSTACK_SIZE    256
#define DICT_SIZE      65536
#define WORD_BUF_SIZE  64

/* Stack */
static long stack[STACK_SIZE];
static int sp = 0;

/* Return stack */
static long rstack[RSTACK_SIZE];
static int rsp = 0;

/* Dictionary */
static char dict[DICT_SIZE];
static int here = 0;

/* State: 0 = interpret, 1 = compile */
static int state = 0;

/* Base for number parsing */
static int base = 10;

/* Word buffer */
static char word_buf[WORD_BUF_SIZE];

/* Input handling */
static int input_char = -2;  /* -2 = need to read, -1 = EOF */

/* Dictionary entry structure (in dict array):
 *   link: 4 bytes (offset to previous entry, 0 = end)
 *   flags: 1 byte (bit 7 = immediate, bits 0-4 = length)
 *   name: N bytes
 *   code: function pointer or data
 */

#define F_IMMED  0x80
#define F_HIDDEN 0x40
#define F_LENMASK 0x1F

/* Latest word in dictionary (offset) */
static int latest = 0;

/* Primitive function type */
typedef void (*primfn)(void);

/* Forward declarations */
static void interpret(void);
static int find_word(const char *name, int len);
static int parse_number(const char *s, int len, long *result);

/* Stack operations */
static void push(long v) {
    if (sp >= STACK_SIZE) { fprintf(stderr, "Stack overflow\n"); exit(1); }
    stack[sp++] = v;
}

static long pop(void) {
    if (sp <= 0) { fprintf(stderr, "Stack underflow\n"); exit(1); }
    return stack[--sp];
}

static void rpush(long v) {
    if (rsp >= RSTACK_SIZE) { fprintf(stderr, "Return stack overflow\n"); exit(1); }
    rstack[rsp++] = v;
}

static long rpop(void) {
    if (rsp <= 0) { fprintf(stderr, "Return stack underflow\n"); exit(1); }
    return rstack[--rsp];
}

/* Input handling */
static int read_char(void) {
    if (input_char == -2) {
        unsigned char c;
        if (read(0, &c, 1) <= 0) return -1;
        return c;
    }
    int c = input_char;
    input_char = -2;
    return c;
}

static void unread_char(int c) {
    input_char = c;
}

/* Read a word from input */
static int read_word(char *buf, int maxlen) {
    int c, len = 0;

    /* Skip whitespace */
    while ((c = read_char()) != -1 && c <= ' ')
        ;

    if (c == -1) return 0;

    /* Read word */
    do {
        if (len < maxlen - 1) buf[len++] = c;
        c = read_char();
    } while (c != -1 && c > ' ');

    if (c != -1) unread_char(c);
    buf[len] = '\0';
    return len;
}

/* ============================================
 * Primitive Words
 * ============================================ */

/* Stack primitives */
static void prim_drop(void) { pop(); }
static void prim_dup(void)  { long a = pop(); push(a); push(a); }
static void prim_swap(void) { long b = pop(), a = pop(); push(b); push(a); }
static void prim_over(void) { long b = pop(), a = pop(); push(a); push(b); push(a); }
static void prim_rot(void)  { long c = pop(), b = pop(), a = pop(); push(b); push(c); push(a); }
static void prim_nip(void)  { long a = pop(); pop(); push(a); }
static void prim_tuck(void) { long b = pop(), a = pop(); push(b); push(a); push(b); }
static void prim_2dup(void) { long b = pop(), a = pop(); push(a); push(b); push(a); push(b); }
static void prim_2drop(void) { pop(); pop(); }
static void prim_2swap(void) { long d = pop(), c = pop(), b = pop(), a = pop(); push(c); push(d); push(a); push(b); }

/* Return stack */
static void prim_tor(void)   { rpush(pop()); }
static void prim_fromr(void) { push(rpop()); }
static void prim_rfetch(void) { push(rstack[rsp-1]); }

/* Arithmetic */
static void prim_plus(void)  { long b = pop(); push(pop() + b); }
static void prim_minus(void) { long b = pop(); push(pop() - b); }
static void prim_star(void)  { long b = pop(); push(pop() * b); }
static void prim_slash(void) { long b = pop(); push(pop() / b); }
static void prim_mod(void)   { long b = pop(); push(pop() % b); }
static void prim_abs(void)   { long a = pop(); push(a < 0 ? -a : a); }
static void prim_negate(void) { push(-pop()); }
static void prim_1plus(void)  { push(pop() + 1); }
static void prim_1minus(void) { push(pop() - 1); }

/* Bitwise */
static void prim_and(void)    { long b = pop(); push(pop() & b); }
static void prim_or(void)     { long b = pop(); push(pop() | b); }
static void prim_xor(void)    { long b = pop(); push(pop() ^ b); }
static void prim_invert(void) { push(~pop()); }
static void prim_lshift(void) { long b = pop(); push(pop() << b); }
static void prim_rshift(void) { long b = pop(); push((unsigned long)pop() >> b); }

/* Comparison */
static void prim_lt(void)    { long b = pop(); push(pop() < b ? -1 : 0); }
static void prim_gt(void)    { long b = pop(); push(pop() > b ? -1 : 0); }
static void prim_eq(void)    { long b = pop(); push(pop() == b ? -1 : 0); }
static void prim_neq(void)   { long b = pop(); push(pop() != b ? -1 : 0); }
static void prim_le(void)    { long b = pop(); push(pop() <= b ? -1 : 0); }
static void prim_ge(void)    { long b = pop(); push(pop() >= b ? -1 : 0); }
static void prim_0eq(void)   { push(pop() == 0 ? -1 : 0); }
static void prim_0lt(void)   { push(pop() < 0 ? -1 : 0); }
static void prim_0gt(void)   { push(pop() > 0 ? -1 : 0); }

/* Memory */
static void prim_fetch(void)  { long *p = (long*)pop(); push(*p); }
static void prim_store(void)  { long *p = (long*)pop(); *p = pop(); }
static void prim_cfetch(void) { char *p = (char*)pop(); push((unsigned char)*p); }
static void prim_cstore(void) { char *p = (char*)pop(); *p = (char)pop(); }

/* I/O */
static void prim_emit(void) {
    char c = (char)pop();
    write(1, &c, 1);
}

static void prim_key(void) {
    int c = read_char();
    push(c == -1 ? 0 : c);
}

static void prim_cr(void) { write(1, "\n", 1); }
static void prim_space(void) { write(1, " ", 1); }

static void prim_dot(void) {
    char buf[24];
    long n = pop();
    int neg = 0, i = 0;

    if (n < 0) { neg = 1; n = -n; }
    if (n == 0) buf[i++] = '0';
    else while (n > 0) {
        int d = n % base;
        buf[i++] = d < 10 ? '0' + d : 'a' + d - 10;
        n /= base;
    }
    if (neg) buf[i++] = '-';
    while (i > 0) write(1, &buf[--i], 1);
    write(1, " ", 1);
}

static void prim_dots(void) {
    printf("<%d> ", sp);
    for (int i = 0; i < sp; i++) printf("%ld ", stack[i]);
    printf("\n");
}

/* Dictionary */
static void prim_here(void)   { push((long)(dict + here)); }
static void prim_latest(void) { push((long)(dict + latest)); }
static void prim_state(void)  { push((long)&state); }
static void prim_base(void)   { push((long)&base); }

static void prim_comma(void) {
    long v = pop();
    *(long*)(dict + here) = v;
    here += sizeof(long);
}

static void prim_ccomma(void) {
    char v = (char)pop();
    dict[here++] = v;
}

static void prim_allot(void) { here += pop(); }
static void prim_align(void) { here = (here + 7) & ~7; }

/* Control */
static void prim_bye(void) { exit(0); }

static void prim_execute(void) {
    primfn fn = (primfn)pop();
    fn();
}

/* Compilation helpers */
static void prim_lbracket(void) { state = 0; }
static void prim_rbracket(void) { state = 1; }
static void prim_immediate(void) {
    /* Mark latest word as immediate */
    dict[latest + 4] |= F_IMMED;
}
static void prim_hidden(void) {
    dict[latest + 4] ^= F_HIDDEN;
}

static void prim_tick(void) {
    int len = read_word(word_buf, WORD_BUF_SIZE);
    if (len == 0) { push(0); return; }
    int entry = find_word(word_buf, len);
    if (entry == 0) { fprintf(stderr, "' unknown word\n"); push(0); return; }
    /* Get code pointer */
    int flags = dict[entry + 4];
    int nlen = flags & F_LENMASK;
    int code_off = entry + 5 + nlen;
    code_off = (code_off + 7) & ~7;
    push(*(long*)(dict + code_off));
}

/* Word definition */
static void prim_colon(void) {
    int len = read_word(word_buf, WORD_BUF_SIZE);
    if (len == 0) return;

    /* Align here */
    here = (here + 7) & ~7;

    /* Write link */
    *(int*)(dict + here) = latest;
    latest = here;
    here += 4;

    /* Write flags + length */
    dict[here++] = len | F_HIDDEN;

    /* Write name */
    memcpy(dict + here, word_buf, len);
    here += len;

    /* Align for code */
    here = (here + 7) & ~7;

    /* Will be filled with code pointer */
    state = 1;  /* Enter compile mode */
}

static void prim_semi(void) {
    /* End definition */
    dict[latest + 4] &= ~F_HIDDEN;  /* Reveal word */
    state = 0;  /* Back to interpret */
}

/* ============================================
 * Dictionary Structure
 * ============================================ */

struct builtin {
    const char *name;
    primfn fn;
    int immediate;
};

static struct builtin builtins[] = {
    /* Stack */
    {"DROP", prim_drop, 0},
    {"DUP", prim_dup, 0},
    {"SWAP", prim_swap, 0},
    {"OVER", prim_over, 0},
    {"ROT", prim_rot, 0},
    {"NIP", prim_nip, 0},
    {"TUCK", prim_tuck, 0},
    {"2DUP", prim_2dup, 0},
    {"2DROP", prim_2drop, 0},
    {"2SWAP", prim_2swap, 0},

    /* Return stack */
    {">R", prim_tor, 0},
    {"R>", prim_fromr, 0},
    {"R@", prim_rfetch, 0},

    /* Arithmetic */
    {"+", prim_plus, 0},
    {"-", prim_minus, 0},
    {"*", prim_star, 0},
    {"/", prim_slash, 0},
    {"MOD", prim_mod, 0},
    {"ABS", prim_abs, 0},
    {"NEGATE", prim_negate, 0},
    {"1+", prim_1plus, 0},
    {"1-", prim_1minus, 0},

    /* Bitwise */
    {"AND", prim_and, 0},
    {"OR", prim_or, 0},
    {"XOR", prim_xor, 0},
    {"INVERT", prim_invert, 0},
    {"LSHIFT", prim_lshift, 0},
    {"RSHIFT", prim_rshift, 0},

    /* Comparison */
    {"<", prim_lt, 0},
    {">", prim_gt, 0},
    {"=", prim_eq, 0},
    {"<>", prim_neq, 0},
    {"<=", prim_le, 0},
    {">=", prim_ge, 0},
    {"0=", prim_0eq, 0},
    {"0<", prim_0lt, 0},
    {"0>", prim_0gt, 0},

    /* Memory */
    {"@", prim_fetch, 0},
    {"!", prim_store, 0},
    {"C@", prim_cfetch, 0},
    {"C!", prim_cstore, 0},

    /* I/O */
    {"EMIT", prim_emit, 0},
    {"KEY", prim_key, 0},
    {"CR", prim_cr, 0},
    {"SPACE", prim_space, 0},
    {".", prim_dot, 0},
    {".S", prim_dots, 0},

    /* Dictionary */
    {"HERE", prim_here, 0},
    {"LATEST", prim_latest, 0},
    {"STATE", prim_state, 0},
    {"BASE", prim_base, 0},
    {",", prim_comma, 0},
    {"C,", prim_ccomma, 0},
    {"ALLOT", prim_allot, 0},
    {"ALIGN", prim_align, 0},

    /* Control */
    {"BYE", prim_bye, 0},
    {"EXECUTE", prim_execute, 0},
    {"[", prim_lbracket, 1},  /* immediate */
    {"]", prim_rbracket, 0},
    {"IMMEDIATE", prim_immediate, 1},  /* immediate */
    {"HIDDEN", prim_hidden, 0},
    {"'", prim_tick, 0},

    /* Definition */
    {":", prim_colon, 0},
    {";", prim_semi, 1},  /* immediate */

    {NULL, NULL, 0}
};

/* ============================================
 * Dictionary Lookup
 * ============================================ */

/* Case-insensitive comparison */
static int streqi(const char *a, const char *b, int len) {
    for (int i = 0; i < len; i++) {
        if (toupper(a[i]) != toupper(b[i])) return 0;
    }
    return 1;
}

/* Find word in dictionary, returns entry offset or 0 */
static int find_word(const char *name, int len) {
    int entry = latest;
    while (entry != 0) {
        int flags = dict[entry + 4];
        if (!(flags & F_HIDDEN)) {
            int nlen = flags & F_LENMASK;
            if (nlen == len && streqi(dict + entry + 5, name, len)) {
                return entry;
            }
        }
        entry = *(int*)(dict + entry);
    }
    return 0;
}

/* Find builtin word by name */
static struct builtin *find_builtin(const char *name, int len) {
    for (int i = 0; builtins[i].name != NULL; i++) {
        int blen = strlen(builtins[i].name);
        if (blen == len && streqi(builtins[i].name, name, len)) {
            return &builtins[i];
        }
    }
    return NULL;
}

/* Parse number in current base */
static int parse_number(const char *s, int len, long *result) {
    long value = 0;
    int neg = 0;
    int i = 0;

    if (len == 0) return 0;

    if (s[0] == '-') { neg = 1; i = 1; }
    if (i >= len) return 0;

    for (; i < len; i++) {
        int digit;
        char c = s[i];
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'z') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') digit = c - 'A' + 10;
        else return 0;

        if (digit >= base) return 0;
        value = value * base + digit;
    }

    *result = neg ? -value : value;
    return 1;
}

/* ============================================
 * Interpreter
 * ============================================ */

static void interpret(void) {
    int len;
    long num;

    while ((len = read_word(word_buf, WORD_BUF_SIZE)) > 0) {
        /* Try builtin first */
        struct builtin *b = find_builtin(word_buf, len);
        if (b != NULL) {
            if (state == 0 || b->immediate) {
                b->fn();
            } else {
                /* Compile: store function pointer */
                *(primfn*)(dict + here) = b->fn;
                here += sizeof(primfn);
            }
            continue;
        }

        /* Try dictionary word */
        int entry = find_word(word_buf, len);
        if (entry != 0) {
            int flags = dict[entry + 4];
            int nlen = flags & F_LENMASK;
            int code_off = entry + 5 + nlen;
            code_off = (code_off + 7) & ~7;
            primfn fn = *(primfn*)(dict + code_off);

            if (state == 0 || (flags & F_IMMED)) {
                fn();
            } else {
                *(primfn*)(dict + here) = fn;
                here += sizeof(primfn);
            }
            continue;
        }

        /* Try number */
        if (parse_number(word_buf, len, &num)) {
            if (state == 0) {
                push(num);
            } else {
                /* Compile literal - for now just push at compile time */
                /* A real Forth would compile LIT + number */
                push(num);
            }
            continue;
        }

        /* Unknown word */
        fprintf(stderr, "%s ? unknown\n", word_buf);
    }
}

/* ============================================
 * Main Entry Point
 * ============================================ */

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    /* Print banner in interactive mode */
    if (isatty(0)) {
        printf("sectorc Stage 1 Forth\n");
        printf("Type 'BYE' to exit\n\n");
    }

    /* Main interpreter loop */
    for (;;) {
        if (isatty(0) && state == 0) {
            printf("> ");
            fflush(stdout);
        }
        interpret();
        if (!isatty(0)) break;  /* Exit on EOF in non-interactive mode */
    }

    return 0;
}
