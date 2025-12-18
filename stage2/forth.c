/*
 * Stage 2: Extended Forth Interpreter
 *
 * A small, auditable Forth system used in the bootstrap chain.
 * Extends Stage 1 with:
 *   - proper colon definitions (LIT/BRANCH/0BRANCH)
 *   - basic string literals (S", .")
 *   - number prefixes ($ hex, # dec, % bin)
 *   - conditional compilation ([IF] [ELSE] [THEN])
 *   - extra arithmetic/stack words used by tests
 *
 * Target: ARM64 macOS (host-built with clang for now).
 */

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef intptr_t Cell;

enum {
    STACK_SIZE = 512,
    RSTACK_SIZE = 512,
    WORD_BUF_SIZE = 256,
    DICT_CELLS = 1 << 16,
    MAX_WORDS = 2048,
    STRING_HEAP_SIZE = 1 << 20,
};

enum {
    F_IMMED = 0x80,
};

struct word;
typedef void (*codefn)(void);

struct word {
    struct word *link;
    char *name;
    uint8_t flags;
    codefn code;
    Cell *param; /* For colon definitions */
};

static Cell stack[STACK_SIZE];
static int sp = 0;

static Cell rstack[RSTACK_SIZE];
static int rsp = 0;

static struct word words[MAX_WORDS];
static int num_words = 0;
static struct word *latest = NULL;

static Cell dict[DICT_CELLS];
static int here = 0; /* Index into dict (cells) */

static Cell *ip = NULL; /* Inner interpreter instruction pointer */
static int state = 0;   /* 0 = interpret, 1 = compile */
static int base = 10;

static struct word *w_lit;
static struct word *w_exit;

static char word_buf[WORD_BUF_SIZE];

static char string_heap[STRING_HEAP_SIZE];
static int string_here = 0;

static void die(const char *msg) {
    write(2, msg, (unsigned)strlen(msg));
    write(2, "\n", 1);
    exit(1);
}

static void push(Cell v) {
    if (sp >= STACK_SIZE) die("stack overflow");
    stack[sp++] = v;
}

static Cell pop(void) {
    if (sp <= 0) die("stack underflow");
    return stack[--sp];
}

static void rpush(Cell v) {
    if (rsp >= RSTACK_SIZE) die("return stack overflow");
    rstack[rsp++] = v;
}

static Cell rpop(void) {
    if (rsp <= 0) die("return stack underflow");
    return rstack[--rsp];
}

static int streqi(const char *a, const char *b) {
    while (*a && *b) {
        if (toupper((unsigned char)*a) != toupper((unsigned char)*b)) return 0;
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

static struct word *find_word(const char *name) {
    for (struct word *w = latest; w; w = w->link) {
        if (streqi(w->name, name)) return w;
    }
    return NULL;
}

static void dict_emit(Cell v) {
    if (here >= DICT_CELLS) die("dictionary overflow");
    dict[here++] = v;
}

static void exec_word(struct word *w);

static void run_inner(void) {
    while (ip) {
        struct word *w = (struct word *)(uintptr_t)*ip++;
        exec_word(w);
    }
}

static void do_colon(void) {
    struct word *self = (struct word *)(uintptr_t)rpop();
    rpush((Cell)(uintptr_t)ip);
    ip = self->param;
    run_inner();
}

static void prim_exit(void) {
    ip = (Cell *)(uintptr_t)rpop();
    if (!ip) return;
}

static void prim_lit(void) {
    push(*ip++);
}

static void prim_branch(void) {
    Cell off = *ip++;
    ip += off;
}

static void prim_0branch(void) {
    Cell flag = pop();
    Cell off = *ip++;
    if (flag == 0) ip += off;
}

static void exec_word(struct word *w) {
    if (!w) die("null word");
    if (w->code == do_colon) {
        rpush((Cell)(uintptr_t)w);
        do_colon();
        return;
    }
    w->code();
}

static int read_char(void) {
    unsigned char c;
    if (read(0, &c, 1) <= 0) return -1;
    return c;
}

static int read_word(char *buf, int maxlen) {
    int c;
    int len = 0;

    do {
        c = read_char();
        if (c < 0) return 0;
    } while (c <= ' ');

    while (c > ' ') {
        if (len < maxlen - 1) buf[len++] = (char)c;
        c = read_char();
        if (c < 0) break;
    }

    buf[len] = '\0';
    return len;
}

static int parse_number(const char *s, Cell *out) {
    int neg = 0;
    int b = base;

    if (*s == '#') { b = 10; s++; }
    else if (*s == '$') { b = 16; s++; }
    else if (*s == '%') { b = 2; s++; }

    if (*s == '-') { neg = 1; s++; }
    if (*s == '\0') return 0;

    Cell v = 0;
    while (*s) {
        int d;
        if (*s >= '0' && *s <= '9') d = *s - '0';
        else if (*s >= 'a' && *s <= 'z') d = *s - 'a' + 10;
        else if (*s >= 'A' && *s <= 'Z') d = *s - 'A' + 10;
        else return 0;
        if (d >= b) return 0;
        v = v * b + d;
        s++;
    }
    *out = neg ? -v : v;
    return 1;
}

static char *alloc_string(int len) {
    int aligned = (string_here + 7) & ~7;
    if (aligned + len + 1 >= STRING_HEAP_SIZE) die("string heap overflow");
    char *p = &string_heap[aligned];
    string_here = aligned + len + 1;
    return p;
}

static int read_until_quote(char *out, int maxlen) {
    int c;
    int len = 0;
    while ((c = read_char()) >= 0) {
        if (c == '"') break;
        if (len < maxlen - 1) out[len++] = (char)c;
    }
    out[len] = '\0';
    return len;
}

/* =============================
 * Primitive words
 * ============================= */

static void prim_drop(void) { pop(); }
static void prim_dup(void) { Cell a = pop(); push(a); push(a); }
static void prim_qdup(void) {
    Cell a = pop();
    push(a);
    if (a != 0) push(a);
}
static void prim_swap(void) { Cell b = pop(), a = pop(); push(b); push(a); }
static void prim_over(void) { Cell b = pop(), a = pop(); push(a); push(b); push(a); }
static void prim_rot(void) { Cell c = pop(), b = pop(), a = pop(); push(b); push(c); push(a); }
static void prim_tuck(void) { Cell b = pop(), a = pop(); push(b); push(a); push(b); }
static void prim_nip(void) { Cell b = pop(); pop(); push(b); }

static void prim_2dup(void) { Cell b = pop(), a = pop(); push(a); push(b); push(a); push(b); }
static void prim_2drop(void) { pop(); pop(); }

static void prim_depth(void) { push(sp); }

static void prim_pick(void) {
    Cell u = pop();
    if (u < 0 || u >= sp) die("PICK range");
    push(stack[sp - 1 - (int)u]);
}

static void prim_plus(void) { Cell b = pop(); push(pop() + b); }
static void prim_minus(void) { Cell b = pop(); push(pop() - b); }
static void prim_star(void) { Cell b = pop(); push(pop() * b); }
static void prim_slash(void) { Cell b = pop(); push(pop() / b); }
static void prim_mod(void) { Cell b = pop(); push(pop() % b); }
static void prim_negate(void) { push(-pop()); }

static void prim_divmod(void) {
    Cell b = pop();
    Cell a = pop();
    push(a % b);
    push(a / b);
}

static void prim_2star(void) { push(pop() * 2); }
static void prim_2slash(void) { push(pop() / 2); }

static void prim_cells(void) { push(pop() * (Cell)sizeof(Cell)); }

static void prim_min(void) { Cell b = pop(), a = pop(); push(a < b ? a : b); }
static void prim_max(void) { Cell b = pop(), a = pop(); push(a > b ? a : b); }

static void prim_lt(void) { Cell b = pop(), a = pop(); push(a < b ? -1 : 0); }
static void prim_gt(void) { Cell b = pop(), a = pop(); push(a > b ? -1 : 0); }
static void prim_eq(void) { Cell b = pop(), a = pop(); push(a == b ? -1 : 0); }
static void prim_0eq(void) { push(pop() == 0 ? -1 : 0); }

static void prim_emit(void) {
    char c = (char)pop();
    write(1, &c, 1);
}

static void prim_space(void) { write(1, " ", 1); }
static void prim_cr(void) { write(1, "\n", 1); }

static void prim_type(void) {
    Cell len = pop();
    const char *addr = (const char *)(uintptr_t)pop();
    if (len > 0) write(1, addr, (size_t)len);
}

static void prim_dot(void) {
    char buf[32];
    Cell n = pop();
    int i = 0;
    int neg = 0;
    if (n < 0) { neg = 1; n = -n; }
    if (n == 0) buf[i++] = '0';
    while (n > 0 && i < (int)sizeof(buf) - 1) {
        int d = (int)(n % base);
        buf[i++] = (char)(d < 10 ? '0' + d : 'a' + (d - 10));
        n /= base;
    }
    if (neg) buf[i++] = '-';
    while (i--) write(1, &buf[i], 1);
    write(1, " ", 1);
}

static void prim_bye(void) { exit(0); }

static void prim_here(void) {
    push((Cell)(uintptr_t)&dict[here]);
}

static void prim_allot(void) {
    Cell n = pop();
    if (n < 0) die("ALLOT negative");
    int cells = (int)((n + (Cell)sizeof(Cell) - 1) / (Cell)sizeof(Cell));
    if (here + cells >= DICT_CELLS) die("dictionary overflow");
    here += cells;
}

static void prim_comma(void) {
    Cell v = pop();
    dict_emit(v);
}

static void prim_ccomma(void) {
    Cell v = pop();
    uint8_t *p = (uint8_t *)&dict[0];
    int byte_here = here * (int)sizeof(Cell);
    if (byte_here >= (int)sizeof(dict)) die("dictionary overflow");
    p[byte_here] = (uint8_t)v;
    byte_here++;
    here = (byte_here + (int)sizeof(Cell) - 1) / (int)sizeof(Cell);
}

static void prim_state(void) { push((Cell)(uintptr_t)&state); }
static void prim_base(void) { push((Cell)(uintptr_t)&base); }

static void prim_lbracket(void) { state = 0; }
static void prim_rbracket(void) { state = 1; }

static void prim_immediate(void) {
    if (!latest) die("no latest");
    latest->flags |= F_IMMED;
}

static void prim_tick(void) {
    if (!read_word(word_buf, WORD_BUF_SIZE)) { push(0); return; }
    struct word *w = find_word(word_buf);
    push((Cell)(uintptr_t)w);
}

static void prim_execute(void) {
    struct word *w = (struct word *)(uintptr_t)pop();
    exec_word(w);
}

static void prim_colon(void) {
    if (!read_word(word_buf, WORD_BUF_SIZE)) die("missing name");

    struct word *w = &words[num_words++];
    memset(w, 0, sizeof(*w));
    w->name = strdup(word_buf);
    w->link = latest;
    w->flags = 0;
    w->code = do_colon;
    w->param = &dict[here];
    latest = w;
    state = 1;
}

static void prim_semicolon(void) {
    if (!w_exit) die("EXIT missing");
    dict_emit((Cell)(uintptr_t)w_exit);
    state = 0;
}

static void prim_backslash(void) {
    int c;
    while ((c = read_char()) >= 0) {
        if (c == '\n') break;
    }
}

static void prim_paren(void) {
    int c;
    while ((c = read_char()) >= 0) {
        if (c == ')') break;
    }
}

/* S" ( -- addr len ) in interpret mode; in compile mode compiles literals */
static void prim_s_quote(void) {
    int len = read_until_quote(word_buf, WORD_BUF_SIZE);
    char *s = alloc_string(len);
    memcpy(s, word_buf, (size_t)len);
    s[len] = '\0';

    if (!state) {
        push((Cell)(uintptr_t)s);
        push((Cell)len);
        return;
    }

    /* Compile: push addr and len at runtime */
    dict_emit((Cell)(uintptr_t)w_lit);
    dict_emit((Cell)(uintptr_t)s);
    dict_emit((Cell)(uintptr_t)w_lit);
    dict_emit((Cell)len);
}

/* ." ( -- ) immediate: interpret prints; compile emits runtime TYPE */
static void prim_dot_quote(void) {
    int len = read_until_quote(word_buf, WORD_BUF_SIZE);
    char *s = alloc_string(len);
    memcpy(s, word_buf, (size_t)len);
    s[len] = '\0';

    if (!state) {
        write(1, s, (size_t)len);
        return;
    }

    /* Compile: push addr/len and TYPE */
    struct word *w_type = find_word("TYPE");
    if (!w_type) die("TYPE missing");
    dict_emit((Cell)(uintptr_t)w_lit);
    dict_emit((Cell)(uintptr_t)s);
    dict_emit((Cell)(uintptr_t)w_lit);
    dict_emit((Cell)len);
    dict_emit((Cell)(uintptr_t)w_type);
}

static int skip_conditional(int stop_on_else) {
    int depth = 1;
    while (read_word(word_buf, WORD_BUF_SIZE)) {
        if (streqi(word_buf, "[IF]")) depth++;
        else if (streqi(word_buf, "[THEN]")) {
            depth--;
            if (depth == 0) return 0;
        } else if (stop_on_else && depth == 1 && streqi(word_buf, "[ELSE]")) {
            return 1;
        }
    }
    return 0;
}

static void prim_bracket_if(void) {
    Cell flag = pop();
    if (flag != 0) return;
    (void)skip_conditional(1);
}

static void prim_bracket_else(void) {
    /* Skip the "else" part (we only reach here if [IF] was true) */
    (void)skip_conditional(0);
}

static void prim_bracket_then(void) {
    /* Marker only */
}

/* =============================
 * Word registration
 * ============================= */

static struct word *add_prim(const char *name, codefn fn, int immediate) {
    if (num_words >= MAX_WORDS) die("too many words");
    struct word *w = &words[num_words++];
    memset(w, 0, sizeof(*w));
    w->name = strdup(name);
    w->link = latest;
    w->flags = (uint8_t)(immediate ? F_IMMED : 0);
    w->code = fn;
    w->param = NULL;
    latest = w;
    return w;
}

static void init_words(void) {
    add_prim("DROP", prim_drop, 0);
    add_prim("DUP", prim_dup, 0);
    add_prim("?DUP", prim_qdup, 0);
    add_prim("SWAP", prim_swap, 0);
    add_prim("OVER", prim_over, 0);
    add_prim("ROT", prim_rot, 0);
    add_prim("TUCK", prim_tuck, 0);
    add_prim("NIP", prim_nip, 0);
    add_prim("2DUP", prim_2dup, 0);
    add_prim("2DROP", prim_2drop, 0);
    add_prim("DEPTH", prim_depth, 0);
    add_prim("PICK", prim_pick, 0);

    add_prim("+", prim_plus, 0);
    add_prim("-", prim_minus, 0);
    add_prim("*", prim_star, 0);
    add_prim("/", prim_slash, 0);
    add_prim("MOD", prim_mod, 0);
    add_prim("/MOD", prim_divmod, 0);
    add_prim("NEGATE", prim_negate, 0);
    add_prim("2*", prim_2star, 0);
    add_prim("2/", prim_2slash, 0);
    add_prim("CELLS", prim_cells, 0);
    add_prim("MIN", prim_min, 0);
    add_prim("MAX", prim_max, 0);

    add_prim("<", prim_lt, 0);
    add_prim(">", prim_gt, 0);
    add_prim("=", prim_eq, 0);
    add_prim("0=", prim_0eq, 0);

    add_prim("EMIT", prim_emit, 0);
    add_prim("SPACE", prim_space, 0);
    add_prim("CR", prim_cr, 0);
    add_prim("TYPE", prim_type, 0);
    add_prim(".", prim_dot, 0);

    add_prim("BYE", prim_bye, 0);

    add_prim("HERE", prim_here, 0);
    add_prim("ALLOT", prim_allot, 0);
    add_prim(",", prim_comma, 0);
    add_prim("C,", prim_ccomma, 0);
    add_prim("STATE", prim_state, 0);
    add_prim("BASE", prim_base, 0);

    add_prim("[", prim_lbracket, 1);
    add_prim("]", prim_rbracket, 0);
    add_prim("IMMEDIATE", prim_immediate, 1);
    add_prim("'", prim_tick, 0);
    add_prim("EXECUTE", prim_execute, 0);

    add_prim("\\", prim_backslash, 1);
    add_prim("(", prim_paren, 1);

    add_prim("S\"", prim_s_quote, 1);
    add_prim(".\"", prim_dot_quote, 1);

    add_prim("[IF]", prim_bracket_if, 1);
    add_prim("[ELSE]", prim_bracket_else, 1);
    add_prim("[THEN]", prim_bracket_then, 1);

    /* Core control for colon words */
    w_lit = add_prim("LIT", prim_lit, 0);
    w_exit = add_prim("EXIT", prim_exit, 0);
    add_prim("BRANCH", prim_branch, 0);
    add_prim("0BRANCH", prim_0branch, 0);
    add_prim(":", prim_colon, 0);
    add_prim(";", prim_semicolon, 1);
}

static void interpret(void) {
    Cell num;
    while (read_word(word_buf, WORD_BUF_SIZE)) {
        struct word *w = find_word(word_buf);
        if (w) {
            if (!state || (w->flags & F_IMMED)) {
                exec_word(w);
            } else {
                dict_emit((Cell)(uintptr_t)w);
            }
            continue;
        }

        if (parse_number(word_buf, &num)) {
            if (!state) push(num);
            else {
                dict_emit((Cell)(uintptr_t)w_lit);
                dict_emit(num);
            }
            continue;
        }

        /* Unknown word: ignore for now */
    }
}

int main(void) {
    if (isatty(0)) {
        printf("sectorc Stage 2 Forth\n");
        printf("Type 'BYE' to exit\n\n");
    }

    init_words();
    interpret();
    return 0;
}
