/*
 * Stage 2: Extended Forth Interpreter
 *
 * Extends Stage 1 with:
 * - String handling
 * - File I/O
 * - Control flow (IF/ELSE/THEN, DO/LOOP, BEGIN/UNTIL, etc.)
 * - Meta-compilation (CREATE/DOES>, DEFER/IS)
 * - Conditional compilation ([IF]/[ELSE]/[THEN])
 *
 * Size target: ~8KB of essential logic
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

/* Stack sizes */
#define STACK_SIZE      256
#define RSTACK_SIZE     256
#define DICT_SIZE       131072
#define WORD_BUF_SIZE   256
#define STRING_SPACE    16384
#define MAX_INCLUDE_DEPTH 8

/* Parameter stack */
static long stack[STACK_SIZE];
static int sp = 0;

/* Return stack */
static long rstack[RSTACK_SIZE];
static int rsp = 0;

/* Dictionary */
static char dict[DICT_SIZE];
static int here = 0;

/* String space */
static char strings[STRING_SPACE];
static int string_ptr = 0;

/* State: 0 = interpret, 1 = compile */
static int state = 0;

/* Base for number parsing */
static int base = 10;

/* Word buffer */
static char word_buf[WORD_BUF_SIZE];

/* Input handling */
static int input_char = -2;

/* Include stack */
static int include_fds[MAX_INCLUDE_DEPTH];
static int include_depth = 0;

/* Latest word in dictionary */
static int latest = 0;

/* Compilation control stack for IF/ELSE/THEN etc */
#define CTRL_STACK_SIZE 64
static int ctrl_stack[CTRL_STACK_SIZE];
static int ctrl_sp = 0;

/* Dictionary flags */
#define F_IMMED    0x80
#define F_HIDDEN   0x40
#define F_LENMASK  0x1F

/* Compiled word types */
typedef void (*primfn)(void);

/* Forward declarations */
static void interpret(void);
static int find_word(const char *name, int len);
static int parse_number(const char *s, int len, long *result);
static int read_word(char *buf, int maxlen);

/* Check dictionary space */
static void check_dict_space(int needed) {
    if (here + needed >= DICT_SIZE) {
        fprintf(stderr, "Dictionary overflow\n");
        exit(1);
    }
}

/* ============================================
 * Stack Operations
 * ============================================ */

static void push(long v) {
    if (sp >= STACK_SIZE) { fprintf(stderr, "Stack overflow\n"); exit(1); }
    stack[sp++] = v;
}

static long pop(void) {
    if (sp <= 0) { fprintf(stderr, "Stack underflow\n"); exit(1); }
    return stack[--sp];
}

static long peek(int n) {
    if (sp - 1 - n < 0) { fprintf(stderr, "Stack underflow\n"); exit(1); }
    return stack[sp - 1 - n];
}

static void rpush(long v) {
    if (rsp >= RSTACK_SIZE) { fprintf(stderr, "Return stack overflow\n"); exit(1); }
    rstack[rsp++] = v;
}

static long rpop(void) {
    if (rsp <= 0) { fprintf(stderr, "Return stack underflow\n"); exit(1); }
    return rstack[--rsp];
}

/* Control stack for compilation */
static void cpush(int v) {
    if (ctrl_sp >= CTRL_STACK_SIZE) { fprintf(stderr, "Control stack overflow\n"); exit(1); }
    ctrl_stack[ctrl_sp++] = v;
}

static int cpop(void) {
    if (ctrl_sp <= 0) { fprintf(stderr, "Control stack underflow\n"); exit(1); }
    return ctrl_stack[--ctrl_sp];
}

/* ============================================
 * Input Handling
 * ============================================ */

static int current_fd(void) {
    return include_depth > 0 ? include_fds[include_depth - 1] : 0;
}

static int read_char(void) {
    if (input_char != -2) {
        int c = input_char;
        input_char = -2;
        return c;
    }

    unsigned char c;
    int fd = current_fd();
    if (read(fd, &c, 1) <= 0) {
        if (include_depth > 0) {
            close(include_fds[--include_depth]);
            return read_char();  /* Continue from parent */
        }
        return -1;
    }
    return c;
}

static void unread_char(int c) {
    input_char = c;
}

static int read_word(char *buf, int maxlen) {
    int c, len = 0;

    while ((c = read_char()) != -1 && c <= ' ')
        ;

    if (c == -1) return 0;

    /* Handle backslash comments */
    if (c == '\\') {
        while ((c = read_char()) != -1 && c != '\n')
            ;
        return read_word(buf, maxlen);
    }

    /* Handle parenthesis comments */
    if (c == '(') {
        int depth = 1;
        while (depth > 0 && (c = read_char()) != -1) {
            if (c == '(') depth++;
            else if (c == ')') depth--;
        }
        return read_word(buf, maxlen);
    }

    do {
        if (len < maxlen - 1) buf[len++] = c;
        c = read_char();
    } while (c != -1 && c > ' ');

    if (c != -1) unread_char(c);
    buf[len] = '\0';
    return len;
}

/* Read string until delimiter */
static int read_string(char *buf, int maxlen, char delim) {
    int c, len = 0;

    while ((c = read_char()) != -1 && c != delim) {
        if (len < maxlen - 1) buf[len++] = c;
    }
    buf[len] = '\0';
    return len;
}

/* ============================================
 * Primitive Words - Stack
 * ============================================ */

static void prim_drop(void) { pop(); }
static void prim_dup(void)  { long a = pop(); push(a); push(a); }
static void prim_swap(void) { long b = pop(), a = pop(); push(b); push(a); }
static void prim_over(void) { long b = pop(), a = pop(); push(a); push(b); push(a); }
static void prim_rot(void)  { long c = pop(), b = pop(), a = pop(); push(b); push(c); push(a); }
static void prim_nip(void)  { long a = pop(); pop(); push(a); }
static void prim_tuck(void) { long b = pop(), a = pop(); push(b); push(a); push(b); }
static void prim_pick(void) { int n = (int)pop(); push(peek(n)); }
static void prim_roll(void) {
    int n = (int)pop();
    if (n <= 0) return;
    long val = stack[sp - 1 - n];
    for (int i = sp - 1 - n; i < sp - 1; i++)
        stack[i] = stack[i + 1];
    stack[sp - 1] = val;
}
static void prim_depth(void) { push(sp); }
static void prim_2dup(void) { long b = pop(), a = pop(); push(a); push(b); push(a); push(b); }
static void prim_2drop(void) { pop(); pop(); }
static void prim_2swap(void) { long d = pop(), c = pop(), b = pop(), a = pop(); push(c); push(d); push(a); push(b); }
static void prim_2over(void) { long d = pop(), c = pop(), b = pop(), a = pop(); push(a); push(b); push(c); push(d); push(a); push(b); }
static void prim_qdup(void) { if (stack[sp-1] != 0) prim_dup(); }

/* Return stack */
static void prim_tor(void)   { rpush(pop()); }
static void prim_fromr(void) { push(rpop()); }
static void prim_rfetch(void) { push(rstack[rsp-1]); }
static void prim_rdrop(void) { rpop(); }

/* ============================================
 * Primitive Words - Arithmetic
 * ============================================ */

static void prim_plus(void)   { long b = pop(); push(pop() + b); }
static void prim_minus(void)  { long b = pop(); push(pop() - b); }
static void prim_star(void)   { long b = pop(); push(pop() * b); }
static void prim_slash(void)  { long b = pop(); push(pop() / b); }
static void prim_mod(void)    { long b = pop(); push(pop() % b); }
static void prim_slashmod(void) {
    long b = pop(), a = pop();
    push(a % b);
    push(a / b);
}
static void prim_abs(void)    { long a = pop(); push(a < 0 ? -a : a); }
static void prim_negate(void) { push(-pop()); }
static void prim_min(void)    { long b = pop(), a = pop(); push(a < b ? a : b); }
static void prim_max(void)    { long b = pop(), a = pop(); push(a > b ? a : b); }
static void prim_1plus(void)  { push(pop() + 1); }
static void prim_1minus(void) { push(pop() - 1); }
static void prim_2star(void)  { push(pop() << 1); }
static void prim_2slash(void) { push(pop() >> 1); }
static void prim_cells(void)  { push(pop() * sizeof(long)); }
static void prim_cellplus(void) { push(pop() + sizeof(long)); }

/* Bitwise */
static void prim_and(void)    { long b = pop(); push(pop() & b); }
static void prim_or(void)     { long b = pop(); push(pop() | b); }
static void prim_xor(void)    { long b = pop(); push(pop() ^ b); }
static void prim_invert(void) { push(~pop()); }
static void prim_lshift(void) { long b = pop(); push(pop() << b); }
static void prim_rshift(void) { long b = pop(); push((unsigned long)pop() >> b); }

/* ============================================
 * Primitive Words - Comparison
 * ============================================ */

static void prim_lt(void)    { long b = pop(); push(pop() < b ? -1 : 0); }
static void prim_gt(void)    { long b = pop(); push(pop() > b ? -1 : 0); }
static void prim_eq(void)    { long b = pop(); push(pop() == b ? -1 : 0); }
static void prim_neq(void)   { long b = pop(); push(pop() != b ? -1 : 0); }
static void prim_le(void)    { long b = pop(); push(pop() <= b ? -1 : 0); }
static void prim_ge(void)    { long b = pop(); push(pop() >= b ? -1 : 0); }
static void prim_0eq(void)   { push(pop() == 0 ? -1 : 0); }
static void prim_0lt(void)   { push(pop() < 0 ? -1 : 0); }
static void prim_0gt(void)   { push(pop() > 0 ? -1 : 0); }
static void prim_0neq(void)  { push(pop() != 0 ? -1 : 0); }
static void prim_ult(void)   { unsigned long b = pop(); push((unsigned long)pop() < b ? -1 : 0); }

/* ============================================
 * Primitive Words - Memory
 * ============================================ */

static void prim_fetch(void)  { long *p = (long*)pop(); push(*p); }
static void prim_store(void)  { long *p = (long*)pop(); *p = pop(); }
static void prim_cfetch(void) { char *p = (char*)pop(); push((unsigned char)*p); }
static void prim_cstore(void) { char *p = (char*)pop(); *p = (char)pop(); }
static void prim_plusstore(void) { long *p = (long*)pop(); *p += pop(); }

static void prim_fill(void) {
    char c = (char)pop();
    long n = pop();
    char *addr = (char*)pop();
    memset(addr, c, n);
}

static void prim_move(void) {
    long n = pop();
    char *dst = (char*)pop();
    char *src = (char*)pop();
    memmove(dst, src, n);
}

static void prim_cmove(void) {
    long n = pop();
    char *dst = (char*)pop();
    char *src = (char*)pop();
    for (long i = 0; i < n; i++)
        dst[i] = src[i];
}

/* ============================================
 * Primitive Words - I/O
 * ============================================ */

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
static void prim_spaces(void) {
    long n = pop();
    while (n-- > 0) write(1, " ", 1);
}

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

static void prim_udot(void) {
    char buf[24];
    unsigned long n = (unsigned long)pop();
    int i = 0;

    if (n == 0) buf[i++] = '0';
    else while (n > 0) {
        int d = n % base;
        buf[i++] = d < 10 ? '0' + d : 'a' + d - 10;
        n /= base;
    }
    while (i > 0) write(1, &buf[--i], 1);
    write(1, " ", 1);
}

static void prim_dots(void) {
    printf("<%d> ", sp);
    for (int i = 0; i < sp; i++) printf("%ld ", stack[i]);
}

static void prim_type(void) {
    long len = pop();
    char *addr = (char*)pop();
    write(1, addr, len);
}

static void prim_count(void) {
    char *addr = (char*)pop();
    push((long)(addr + 1));
    push((unsigned char)*addr);
}

/* ============================================
 * Primitive Words - Strings
 * ============================================ */

/* S" - parse string literal */
static void prim_squote(void) {
    char buf[256];
    int len = read_string(buf, sizeof(buf), '"');

    if (state == 0) {
        /* Interpret mode: put in string space */
        if (string_ptr + len >= STRING_SPACE) {
            fprintf(stderr, "String space overflow\n");
            exit(1);
        }
        char *dest = strings + string_ptr;
        memcpy(dest, buf, len);
        string_ptr += len;
        push((long)dest);
        push(len);
    } else {
        /* Compile mode: embed string in definition */
        /* For simplicity, we put the string address and length as literals */
        check_dict_space(len);
        char *dest = dict + here;
        memcpy(dest, buf, len);
        here += len;
        
        int aligned = (here + 7) & ~7;
        check_dict_space(aligned - here);
        here = aligned;
        
        push((long)dest);
        push(len);
    }
}

/* ." - print string literal */
static void prim_dotquote(void) {
    char buf[256];
    int len = read_string(buf, sizeof(buf), '"');
    write(1, buf, len);
}

/* Compare strings */
static void prim_compare(void) {
    long len2 = pop();
    char *s2 = (char*)pop();
    long len1 = pop();
    char *s1 = (char*)pop();

    long minlen = len1 < len2 ? len1 : len2;
    for (long i = 0; i < minlen; i++) {
        if (s1[i] < s2[i]) { push(-1); return; }
        if (s1[i] > s2[i]) { push(1); return; }
    }
    if (len1 < len2) push(-1);
    else if (len1 > len2) push(1);
    else push(0);
}

/* ============================================
 * Primitive Words - Dictionary
 * ============================================ */

static void prim_here(void)   { push((long)(dict + here)); }
static void prim_latest(void) { push((long)&latest); }
static void prim_state(void)  { push((long)&state); }
static void prim_base(void)   { push((long)&base); }

static void prim_comma(void) {
    long v = pop();
    check_dict_space(sizeof(long));
    *(long*)(dict + here) = v;
    here += sizeof(long);
}

static void prim_ccomma(void) {
    char v = (char)pop();
    check_dict_space(1);
    dict[here++] = v;
}

static void prim_allot(void) {
    int n = (int)pop();
    check_dict_space(n);
    here += n;
}

static void prim_align(void) {
    int aligned = (here + 7) & ~7;
    check_dict_space(aligned - here);
    here = aligned;
}
static void prim_aligned(void) { long a = pop(); push((a + 7) & ~7); }

/* ============================================
 * Primitive Words - Control Flow
 * ============================================ */

static void prim_bye(void) { exit(0); }

static void prim_execute(void) {
    primfn fn = (primfn)pop();
    fn();
}

/* IF/ELSE/THEN (immediate, for compilation) */
static void prim_if(void) {
    /* Compile conditional branch placeholder */
    cpush(here);  /* Remember location for backpatching */
    push(0);      /* Placeholder */
    prim_comma();
    cpush(1);     /* Mark as IF */
}

static void prim_else(void) {
    int type = cpop();
    if (type != 1) { fprintf(stderr, "ELSE without IF\n"); return; }
    int if_loc = cpop();

    /* Compile unconditional branch */
    cpush(here);
    push(0);
    prim_comma();
    cpush(2);  /* Mark as ELSE */

    /* Backpatch IF */
    *(long*)(dict + if_loc) = here;
}

static void prim_then(void) {
    int type = cpop();
    int loc = cpop();
    if (type != 1 && type != 2) { fprintf(stderr, "THEN without IF\n"); return; }
    *(long*)(dict + loc) = here;
}

/* BEGIN/UNTIL/AGAIN/WHILE/REPEAT */
static void prim_begin(void) {
    cpush(here);
    cpush(3);  /* Mark as BEGIN */
}

static void prim_until(void) {
    int type = cpop();
    int loc = cpop();
    if (type != 3) { fprintf(stderr, "UNTIL without BEGIN\n"); return; }
    push(loc);
    prim_comma();
}

static void prim_again(void) {
    int type = cpop();
    int loc = cpop();
    if (type != 3) { fprintf(stderr, "AGAIN without BEGIN\n"); return; }
    push(loc);
    prim_comma();
}

static void prim_while(void) {
    int type = cpop();
    int begin_loc = cpop();
    if (type != 3) { fprintf(stderr, "WHILE without BEGIN\n"); return; }

    cpush(begin_loc);
    cpush(here);  /* Save WHILE location for backpatching */
    push(0);
    prim_comma();
    cpush(4);  /* Mark as WHILE */
}

static void prim_repeat(void) {
    int type = cpop();
    if (type != 4) { fprintf(stderr, "REPEAT without WHILE\n"); return; }
    int while_loc = cpop();
    int begin_loc = cpop();

    push(begin_loc);
    prim_comma();
    *(long*)(dict + while_loc) = here;
}

/* DO/LOOP/+LOOP */
static void prim_do(void) {
    cpush(here);
    cpush(5);  /* Mark as DO */
}

static void prim_loop(void) {
    int type = cpop();
    int loc = cpop();
    if (type != 5) { fprintf(stderr, "LOOP without DO\n"); return; }
    push(loc);
    prim_comma();
}

static void prim_plusloop(void) {
    int type = cpop();
    int loc = cpop();
    if (type != 5) { fprintf(stderr, "+LOOP without DO\n"); return; }
    push(loc);
    prim_comma();
}

static void prim_i(void) { push(rstack[rsp-1]); }
static void prim_j(void) { push(rstack[rsp-3]); }
static void prim_leave(void) { /* TODO: implement leave */ }
static void prim_unloop(void) { rpop(); rpop(); }

/* ============================================
 * Primitive Words - Compilation
 * ============================================ */

static void prim_lbracket(void) { state = 0; }
static void prim_rbracket(void) { state = 1; }
static void prim_immediate(void) {
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
    int flags = dict[entry + 4];
    int nlen = flags & F_LENMASK;
    int code_off = entry + 5 + nlen;
    code_off = (code_off + 7) & ~7;
    push(*(long*)(dict + code_off));
}

static void prim_brackettick(void) {
    prim_tick();
}

/* Word definition */
static void prim_colon(void) {
    int len = read_word(word_buf, WORD_BUF_SIZE);
    if (len == 0) return;

    int aligned = (here + 7) & ~7;
    check_dict_space(aligned - here);
    here = aligned;

    check_dict_space(4);
    *(int*)(dict + here) = latest;
    latest = here;
    here += 4;
    check_dict_space(1 + len);
    dict[here++] = len | F_HIDDEN;
    memcpy(dict + here, word_buf, len);
    here += len;
    
    aligned = (here + 7) & ~7;
    check_dict_space(aligned - here);
    here = aligned;
    state = 1;
}

static void prim_semi(void) {
    dict[latest + 4] &= ~F_HIDDEN;
    state = 0;
}

/* CREATE/DOES> */
static void prim_create(void) {
    int len = read_word(word_buf, WORD_BUF_SIZE);
    if (len == 0) return;

    int aligned = (here + 7) & ~7;
    check_dict_space(aligned - here);
    here = aligned;

    check_dict_space(4);
    *(int*)(dict + here) = latest;
    latest = here;
    here += 4;
    check_dict_space(1 + len);
    dict[here++] = len;
    memcpy(dict + here, word_buf, len);
    here += len;
    
    aligned = (here + 7) & ~7;
    check_dict_space(aligned - here);
    here = aligned;
    /* Store a placeholder code pointer */
    check_dict_space(sizeof(long));
    *(long*)(dict + here) = 0;
    here += sizeof(long);
}

static void prim_does(void) {
    /* TODO: implement DOES> properly */
}

/* VARIABLE/CONSTANT */
static void prim_variable(void) {
    prim_create();
    push(0);
    prim_comma();
}

static void prim_constant(void) {
    long val = pop();
    prim_create();
    push(val);
    prim_comma();
}

/* ============================================
 * Primitive Words - File I/O
 * ============================================ */

static void prim_openfile(void) {
    long mode = pop();
    long len = pop();
    char *name = (char*)pop();

    char namebuf[256];
    if (len >= (int)sizeof(namebuf)) len = sizeof(namebuf) - 1;
    memcpy(namebuf, name, len);
    namebuf[len] = '\0';

    int flags = 0;
    if (mode == 0) flags = O_RDONLY;
    else if (mode == 1) flags = O_WRONLY | O_CREAT | O_TRUNC;
    else flags = O_RDWR | O_CREAT;

    int fd = open(namebuf, flags, 0644);
    push(fd);
    push(fd < 0 ? -1 : 0);  /* ior */
}

static void prim_closefile(void) {
    int fd = (int)pop();
    int r = close(fd);
    push(r < 0 ? -1 : 0);
}

static void prim_readfile(void) {
    int fd = (int)pop();
    long len = pop();
    char *buf = (char*)pop();

    ssize_t n = read(fd, buf, len);
    push(n >= 0 ? n : 0);
    push(n < 0 ? -1 : 0);
}

static void prim_writefile(void) {
    int fd = (int)pop();
    long len = pop();
    char *buf = (char*)pop();

    ssize_t n = write(fd, buf, len);
    push(n < 0 ? -1 : 0);
}

static void prim_readline(void) {
    int fd = (int)pop();
    long maxlen = pop();
    char *buf = (char*)pop();

    long len = 0;
    char c;
    while (len < maxlen - 1) {
        ssize_t n = read(fd, &c, 1);
        if (n <= 0) break;
        if (c == '\n') break;
        buf[len++] = c;
    }
    buf[len] = '\0';
    push(len);
    push(len > 0 ? -1 : 0);  /* flag */
    push(0);  /* ior */
}

static void prim_include(void) {
    int len = read_word(word_buf, WORD_BUF_SIZE);
    if (len == 0) return;

    word_buf[len] = '\0';
    int fd = open(word_buf, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Cannot open: %s\n", word_buf);
        return;
    }

    if (include_depth >= MAX_INCLUDE_DEPTH) {
        fprintf(stderr, "Include depth exceeded\n");
        close(fd);
        return;
    }

    include_fds[include_depth++] = fd;
}

static void prim_included(void) {
    long len = pop();
    char *name = (char*)pop();

    char namebuf[256];
    if (len >= (int)sizeof(namebuf)) len = sizeof(namebuf) - 1;
    memcpy(namebuf, name, len);
    namebuf[len] = '\0';

    int fd = open(namebuf, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Cannot open: %s\n", namebuf);
        return;
    }

    if (include_depth >= MAX_INCLUDE_DEPTH) {
        fprintf(stderr, "Include depth exceeded\n");
        close(fd);
        return;
    }

    include_fds[include_depth++] = fd;
}

/* ============================================
 * Primitive Words - Conditional Compilation
 * ============================================ */

static void prim_bracketif(void) {
    long flag = pop();
    if (flag) return;  /* Condition true, continue normally */

    /* Skip until [ELSE] or [THEN] */
    int depth = 1;
    while (depth > 0) {
        int len = read_word(word_buf, WORD_BUF_SIZE);
        if (len == 0) break;
        if (strcasecmp(word_buf, "[IF]") == 0) depth++;
        else if (strcasecmp(word_buf, "[ELSE]") == 0 && depth == 1) return;
        else if (strcasecmp(word_buf, "[THEN]") == 0) depth--;
    }
}

static void prim_bracketelse(void) {
    /* Skip until [THEN] */
    int depth = 1;
    while (depth > 0) {
        int len = read_word(word_buf, WORD_BUF_SIZE);
        if (len == 0) break;
        if (strcasecmp(word_buf, "[IF]") == 0) depth++;
        else if (strcasecmp(word_buf, "[THEN]") == 0) depth--;
    }
}

static void prim_bracketthen(void) {
    /* No-op */
}

/* ============================================
 * Builtin Dictionary
 * ============================================ */

struct builtin {
    const char *name;
    primfn fn;
    int immediate;
};

static struct builtin builtins[] = {
    /* Stack */
    {"DROP", prim_drop, 0}, {"DUP", prim_dup, 0}, {"SWAP", prim_swap, 0},
    {"OVER", prim_over, 0}, {"ROT", prim_rot, 0}, {"NIP", prim_nip, 0},
    {"TUCK", prim_tuck, 0}, {"PICK", prim_pick, 0}, {"ROLL", prim_roll, 0},
    {"DEPTH", prim_depth, 0}, {"?DUP", prim_qdup, 0},
    {"2DUP", prim_2dup, 0}, {"2DROP", prim_2drop, 0},
    {"2SWAP", prim_2swap, 0}, {"2OVER", prim_2over, 0},
    {">R", prim_tor, 0}, {"R>", prim_fromr, 0}, {"R@", prim_rfetch, 0}, {"RDROP", prim_rdrop, 0},

    /* Arithmetic */
    {"+", prim_plus, 0}, {"-", prim_minus, 0}, {"*", prim_star, 0},
    {"/", prim_slash, 0}, {"MOD", prim_mod, 0}, {"/MOD", prim_slashmod, 0},
    {"ABS", prim_abs, 0}, {"NEGATE", prim_negate, 0},
    {"MIN", prim_min, 0}, {"MAX", prim_max, 0},
    {"1+", prim_1plus, 0}, {"1-", prim_1minus, 0},
    {"2*", prim_2star, 0}, {"2/", prim_2slash, 0},
    {"CELLS", prim_cells, 0}, {"CELL+", prim_cellplus, 0},

    /* Bitwise */
    {"AND", prim_and, 0}, {"OR", prim_or, 0}, {"XOR", prim_xor, 0},
    {"INVERT", prim_invert, 0}, {"LSHIFT", prim_lshift, 0}, {"RSHIFT", prim_rshift, 0},

    /* Comparison */
    {"<", prim_lt, 0}, {">", prim_gt, 0}, {"=", prim_eq, 0},
    {"<>", prim_neq, 0}, {"<=", prim_le, 0}, {">=", prim_ge, 0},
    {"0=", prim_0eq, 0}, {"0<", prim_0lt, 0}, {"0>", prim_0gt, 0}, {"0<>", prim_0neq, 0},
    {"U<", prim_ult, 0},

    /* Memory */
    {"@", prim_fetch, 0}, {"!", prim_store, 0},
    {"C@", prim_cfetch, 0}, {"C!", prim_cstore, 0},
    {"+!", prim_plusstore, 0},
    {"FILL", prim_fill, 0}, {"MOVE", prim_move, 0}, {"CMOVE", prim_cmove, 0},

    /* I/O */
    {"EMIT", prim_emit, 0}, {"KEY", prim_key, 0},
    {"CR", prim_cr, 0}, {"SPACE", prim_space, 0}, {"SPACES", prim_spaces, 0},
    {".", prim_dot, 0}, {"U.", prim_udot, 0}, {".S", prim_dots, 0},
    {"TYPE", prim_type, 0}, {"COUNT", prim_count, 0},

    /* Strings */
    {"S\"", prim_squote, 1},
    {".\"", prim_dotquote, 1},
    {"COMPARE", prim_compare, 0},

    /* Dictionary */
    {"HERE", prim_here, 0}, {"LATEST", prim_latest, 0},
    {"STATE", prim_state, 0}, {"BASE", prim_base, 0},
    {",", prim_comma, 0}, {"C,", prim_ccomma, 0},
    {"ALLOT", prim_allot, 0}, {"ALIGN", prim_align, 0}, {"ALIGNED", prim_aligned, 0},

    /* Control */
    {"BYE", prim_bye, 0}, {"EXECUTE", prim_execute, 0},
    {"[", prim_lbracket, 1}, {"]", prim_rbracket, 0},
    {"IMMEDIATE", prim_immediate, 1}, {"HIDDEN", prim_hidden, 0},
    {"'", prim_tick, 0}, {"[']", prim_brackettick, 1},

    /* Control flow */
    {"IF", prim_if, 1}, {"ELSE", prim_else, 1}, {"THEN", prim_then, 1},
    {"BEGIN", prim_begin, 1}, {"UNTIL", prim_until, 1}, {"AGAIN", prim_again, 1},
    {"WHILE", prim_while, 1}, {"REPEAT", prim_repeat, 1},
    {"DO", prim_do, 1}, {"LOOP", prim_loop, 1}, {"+LOOP", prim_plusloop, 1},
    {"I", prim_i, 0}, {"J", prim_j, 0}, {"LEAVE", prim_leave, 0}, {"UNLOOP", prim_unloop, 0},

    /* Definition */
    {":", prim_colon, 0}, {";", prim_semi, 1},
    {"CREATE", prim_create, 0}, {"DOES>", prim_does, 1},
    {"VARIABLE", prim_variable, 0}, {"CONSTANT", prim_constant, 0},

    /* File I/O */
    {"OPEN-FILE", prim_openfile, 0}, {"CLOSE-FILE", prim_closefile, 0},
    {"READ-FILE", prim_readfile, 0}, {"WRITE-FILE", prim_writefile, 0},
    {"READ-LINE", prim_readline, 0},
    {"INCLUDE", prim_include, 0}, {"INCLUDED", prim_included, 0},

    /* Conditional compilation */
    {"[IF]", prim_bracketif, 1},
    {"[ELSE]", prim_bracketelse, 1},
    {"[THEN]", prim_bracketthen, 1},

    {NULL, NULL, 0}
};

/* ============================================
 * Dictionary Lookup
 * ============================================ */

static int streqi(const char *a, const char *b, int len) {
    for (int i = 0; i < len; i++) {
        if (toupper(a[i]) != toupper(b[i])) return 0;
    }
    return 1;
}

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

static struct builtin *find_builtin(const char *name, int len) {
    for (int i = 0; builtins[i].name != NULL; i++) {
        int blen = strlen(builtins[i].name);
        if (blen == len && streqi(builtins[i].name, name, len)) {
            return &builtins[i];
        }
    }
    return NULL;
}

static int parse_number(const char *s, int len, long *result) {
    long value = 0;
    int neg = 0;
    int i = 0;
    int num_base = base;

    if (len == 0) return 0;

    /* Check for base prefix */
    if (len > 1 && s[0] == '$') { num_base = 16; i = 1; }
    else if (len > 1 && s[0] == '#') { num_base = 10; i = 1; }
    else if (len > 1 && s[0] == '%') { num_base = 2; i = 1; }

    if (s[i] == '-') { neg = 1; i++; }
    if (i >= len) return 0;

    for (; i < len; i++) {
        int digit;
        char c = s[i];
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'z') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') digit = c - 'A' + 10;
        else return 0;

        if (digit >= num_base) return 0;
        value = value * num_base + digit;
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
        struct builtin *b = find_builtin(word_buf, len);
        if (b != NULL) {
            if (state == 0 || b->immediate) {
                b->fn();
            } else {
                check_dict_space(sizeof(primfn));
                *(primfn*)(dict + here) = b->fn;
                here += sizeof(primfn);
            }
            continue;
        }

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
                check_dict_space(sizeof(primfn));
                *(primfn*)(dict + here) = fn;
                here += sizeof(primfn);
            }
            continue;
        }

        if (parse_number(word_buf, len, &num)) {
            if (state == 0) {
                push(num);
            } else {
                push(num);
            }
            continue;
        }

        fprintf(stderr, "%s ? unknown\n", word_buf);
    }
}

/* ============================================
 * Main
 * ============================================ */

int main(int argc, char **argv) {
    /* Process command line file arguments */
    for (int i = 1; i < argc; i++) {
        int fd = open(argv[i], O_RDONLY);
        if (fd < 0) {
            fprintf(stderr, "Cannot open: %s\n", argv[i]);
            continue;
        }
        include_fds[include_depth++] = fd;
    }

    if (isatty(0) && include_depth == 0) {
        printf("sectorc Stage 2 Forth\n");
        printf("Type 'BYE' to exit\n\n");
    }

    for (;;) {
        if (isatty(current_fd()) && state == 0) {
            printf("> ");
            fflush(stdout);
        }
        interpret();
        if (include_depth == 0 && !isatty(0)) break;
        if (include_depth == 0 && isatty(0)) continue;
    }

    return 0;
}
