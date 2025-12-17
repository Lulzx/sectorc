/*
 * Stage 3: Subset C Compiler
 *
 * A minimal C compiler for ARM64 macOS.
 * Compiles a useful subset of C to ARM64 assembly.
 *
 * Supported:
 *   Types: int, char, void, T*, T[]
 *   Statements: if/else, while, for, return, {}
 *   Expressions: arithmetic, comparison, logical, assignment,
 *                function calls, array indexing, pointer deref
 *   Declarations: functions, global/local variables
 *   Preprocessor: #define (object-like), #include
 *
 * Size target: ~15KB of essential logic
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

/* ============================================
 * Constants and Limits
 * ============================================ */

#define MAX_TOKEN    256
#define MAX_IDENT    64
#define MAX_SYMBOLS  1024
#define MAX_STRINGS  256
#define MAX_DEFINES  256
#define MAX_LOCALS   64
#define STACK_SIZE   256

/* Token types */
enum {
    TK_EOF = 0,
    TK_NUM,         /* Number literal */
    TK_CHAR,        /* Character literal */
    TK_STR,         /* String literal */
    TK_IDENT,       /* Identifier */
    /* Keywords */
    TK_INT, TK_CHAR_KW, TK_VOID, TK_IF, TK_ELSE, TK_WHILE,
    TK_FOR, TK_RETURN, TK_SIZEOF, TK_BREAK, TK_CONTINUE,
    /* Operators */
    TK_PLUS, TK_MINUS, TK_STAR, TK_SLASH, TK_MOD,
    TK_AND, TK_OR, TK_XOR, TK_NOT, TK_TILDE,
    TK_LT, TK_GT, TK_LE, TK_GE, TK_EQ, TK_NE,
    TK_LAND, TK_LOR, TK_LNOT,
    TK_ASSIGN, TK_PLUSEQ, TK_MINUSEQ, TK_STAREQ, TK_SLASHEQ,
    TK_INC, TK_DEC,
    TK_LSHIFT, TK_RSHIFT,
    TK_ARROW, TK_DOT,
    /* Delimiters */
    TK_LPAREN, TK_RPAREN, TK_LBRACE, TK_RBRACE,
    TK_LBRACKET, TK_RBRACKET,
    TK_COMMA, TK_SEMI, TK_COLON, TK_QUEST,
    TK_AMP,
};

/* Symbol types */
enum {
    SYM_GLOBAL,
    SYM_LOCAL,
    SYM_FUNC,
    SYM_PARAM,
};

/* Type sizes */
#define SIZE_CHAR   1
#define SIZE_INT    8
#define SIZE_PTR    8

/* ============================================
 * Global State
 * ============================================ */

/* Input handling */
static FILE *input_file;
static const char *input_filename;
static int line_num = 1;
static int ch;              /* Current character */
static int token;           /* Current token */
static long token_val;      /* Token numeric value */
static char token_str[MAX_TOKEN];  /* Token string */

/* Output */
static FILE *output_file;

/* Symbol table */
struct symbol {
    char name[MAX_IDENT];
    int type;       /* SYM_* */
    int data_type;  /* Type info */
    int ptr_level;  /* Pointer depth */
    int offset;     /* Stack offset for locals */
    int size;       /* Array size */
};
static struct symbol symbols[MAX_SYMBOLS];
static int num_symbols = 0;

/* Local variables */
static struct symbol locals[MAX_LOCALS];
static int num_locals = 0;
static int local_offset = 0;  /* Current stack offset */

/* String literals */
static char *string_table[MAX_STRINGS];
static int num_strings = 0;

/* Preprocessor defines */
struct define {
    char name[MAX_IDENT];
    char value[MAX_TOKEN];
};
static struct define defines[MAX_DEFINES];
static int num_defines = 0;

/* Code generation */
static int label_count = 0;
static int current_break_label = -1;
static int current_continue_label = -1;
static int current_frame_size = 0;

/* ============================================
 * Error Handling
 * ============================================ */

static void error(const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: error: ", input_filename, line_num);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    exit(1);
}

/* ============================================
 * Lexer
 * ============================================ */

static void next_char(void) {
    ch = fgetc(input_file);
    if (ch == '\n') line_num++;
}

static void skip_whitespace(void) {
    while (isspace(ch)) next_char();
}

static void skip_line_comment(void) {
    while (ch != '\n' && ch != EOF) next_char();
}

static void skip_block_comment(void) {
    next_char();  /* Skip * */
    while (ch != EOF) {
        if (ch == '*') {
            next_char();
            if (ch == '/') {
                next_char();
                return;
            }
        } else {
            next_char();
        }
    }
    error("unterminated block comment");
}

static int is_ident_start(int c) {
    return isalpha(c) || c == '_';
}

static int is_ident_char(int c) {
    return isalnum(c) || c == '_';
}

static int check_keyword(const char *s) {
    if (strcmp(s, "int") == 0) return TK_INT;
    if (strcmp(s, "char") == 0) return TK_CHAR_KW;
    if (strcmp(s, "void") == 0) return TK_VOID;
    if (strcmp(s, "if") == 0) return TK_IF;
    if (strcmp(s, "else") == 0) return TK_ELSE;
    if (strcmp(s, "while") == 0) return TK_WHILE;
    if (strcmp(s, "for") == 0) return TK_FOR;
    if (strcmp(s, "return") == 0) return TK_RETURN;
    if (strcmp(s, "sizeof") == 0) return TK_SIZEOF;
    if (strcmp(s, "break") == 0) return TK_BREAK;
    if (strcmp(s, "continue") == 0) return TK_CONTINUE;
    return TK_IDENT;
}

/* Check for preprocessor define */
static int check_define(const char *s) {
    for (int i = 0; i < num_defines; i++) {
        if (strcmp(defines[i].name, s) == 0) {
            return i;
        }
    }
    return -1;
}

static int read_escape(void) {
    next_char();
    switch (ch) {
        case 'n': return '\n';
        case 't': return '\t';
        case 'r': return '\r';
        case '0': return '\0';
        case '\\': return '\\';
        case '\'': return '\'';
        case '"': return '"';
        default: return ch;
    }
}

static void next_token(void);

static void handle_preprocessor(void) {
    /* Skip # */
    next_char();
    skip_whitespace();

    /* Read directive */
    int i = 0;
    while (is_ident_char(ch) && i < MAX_IDENT - 1) {
        token_str[i++] = ch;
        next_char();
    }
    token_str[i] = '\0';

    if (strcmp(token_str, "define") == 0) {
        skip_whitespace();
        /* Read name */
        i = 0;
        while (is_ident_char(ch) && i < MAX_IDENT - 1) {
            defines[num_defines].name[i++] = ch;
            next_char();
        }
        defines[num_defines].name[i] = '\0';

        skip_whitespace();
        /* Read value */
        i = 0;
        while (ch != '\n' && ch != EOF && i < MAX_TOKEN - 1) {
            defines[num_defines].value[i++] = ch;
            next_char();
        }
        defines[num_defines].value[i] = '\0';
        num_defines++;
    } else if (strcmp(token_str, "include") == 0) {
        skip_whitespace();
        /* Skip include for now - simple implementation */
        while (ch != '\n' && ch != EOF) next_char();
    } else {
        /* Unknown directive, skip line */
        while (ch != '\n' && ch != EOF) next_char();
    }

    next_token();
}

static void next_token(void) {
again:
    skip_whitespace();

    if (ch == EOF) {
        token = TK_EOF;
        return;
    }

    /* Preprocessor */
    if (ch == '#') {
        handle_preprocessor();
        return;
    }

    /* Comments */
    if (ch == '/') {
        next_char();
        if (ch == '/') {
            skip_line_comment();
            goto again;
        } else if (ch == '*') {
            skip_block_comment();
            goto again;
        } else if (ch == '=') {
            next_char();
            token = TK_SLASHEQ;
            return;
        } else {
            token = TK_SLASH;
            return;
        }
    }

    /* Identifiers and keywords */
    if (is_ident_start(ch)) {
        int i = 0;
        while (is_ident_char(ch) && i < MAX_TOKEN - 1) {
            token_str[i++] = ch;
            next_char();
        }
        token_str[i] = '\0';

        /* Check for define */
        int def_idx = check_define(token_str);
        if (def_idx >= 0) {
            /* Substitute define value */
            /* For simple defines, parse the value as a number */
            token_val = strtol(defines[def_idx].value, NULL, 0);
            token = TK_NUM;
            return;
        }

        token = check_keyword(token_str);
        return;
    }

    /* Numbers */
    if (isdigit(ch)) {
        token_val = 0;
        if (ch == '0') {
            next_char();
            if (ch == 'x' || ch == 'X') {
                next_char();
                while (isxdigit(ch)) {
                    token_val = token_val * 16;
                    if (ch >= '0' && ch <= '9') token_val += ch - '0';
                    else token_val += (ch | 0x20) - 'a' + 10;
                    next_char();
                }
            } else {
                while (ch >= '0' && ch <= '7') {
                    token_val = token_val * 8 + ch - '0';
                    next_char();
                }
            }
        } else {
            while (isdigit(ch)) {
                token_val = token_val * 10 + ch - '0';
                next_char();
            }
        }
        token = TK_NUM;
        return;
    }

    /* Character literal */
    if (ch == '\'') {
        next_char();
        if (ch == '\\') {
            token_val = read_escape();
        } else {
            token_val = ch;
        }
        next_char();
        if (ch != '\'') error("expected closing quote");
        next_char();
        token = TK_CHAR;
        return;
    }

    /* String literal */
    if (ch == '"') {
        next_char();
        int i = 0;
        while (ch != '"' && ch != EOF && i < MAX_TOKEN - 1) {
            if (ch == '\\') {
                token_str[i++] = read_escape();
            } else {
                token_str[i++] = ch;
            }
            next_char();
        }
        token_str[i] = '\0';
        if (ch != '"') error("unterminated string");
        next_char();
        token = TK_STR;
        return;
    }

    /* Operators and delimiters */
    int c = ch;
    next_char();

    switch (c) {
        case '+':
            if (ch == '+') { next_char(); token = TK_INC; }
            else if (ch == '=') { next_char(); token = TK_PLUSEQ; }
            else token = TK_PLUS;
            break;
        case '-':
            if (ch == '-') { next_char(); token = TK_DEC; }
            else if (ch == '=') { next_char(); token = TK_MINUSEQ; }
            else if (ch == '>') { next_char(); token = TK_ARROW; }
            else token = TK_MINUS;
            break;
        case '*':
            if (ch == '=') { next_char(); token = TK_STAREQ; }
            else token = TK_STAR;
            break;
        case '%': token = TK_MOD; break;
        case '&':
            if (ch == '&') { next_char(); token = TK_LAND; }
            else token = TK_AMP;
            break;
        case '|':
            if (ch == '|') { next_char(); token = TK_LOR; }
            else token = TK_OR;
            break;
        case '^': token = TK_XOR; break;
        case '~': token = TK_TILDE; break;
        case '<':
            if (ch == '=') { next_char(); token = TK_LE; }
            else if (ch == '<') { next_char(); token = TK_LSHIFT; }
            else token = TK_LT;
            break;
        case '>':
            if (ch == '=') { next_char(); token = TK_GE; }
            else if (ch == '>') { next_char(); token = TK_RSHIFT; }
            else token = TK_GT;
            break;
        case '=':
            if (ch == '=') { next_char(); token = TK_EQ; }
            else token = TK_ASSIGN;
            break;
        case '!':
            if (ch == '=') { next_char(); token = TK_NE; }
            else token = TK_LNOT;
            break;
        case '(': token = TK_LPAREN; break;
        case ')': token = TK_RPAREN; break;
        case '{': token = TK_LBRACE; break;
        case '}': token = TK_RBRACE; break;
        case '[': token = TK_LBRACKET; break;
        case ']': token = TK_RBRACKET; break;
        case ',': token = TK_COMMA; break;
        case ';': token = TK_SEMI; break;
        case ':': token = TK_COLON; break;
        case '?': token = TK_QUEST; break;
        case '.': token = TK_DOT; break;
        default: error("unknown character: %c", c);
    }
}

static void expect(int tk) {
    if (token != tk) {
        error("expected token %d, got %d", tk, token);
    }
    next_token();
}

/* ============================================
 * Symbol Table
 * ============================================ */

static struct symbol *find_symbol(const char *name) {
    /* Check locals first */
    for (int i = num_locals - 1; i >= 0; i--) {
        if (strcmp(locals[i].name, name) == 0) {
            return &locals[i];
        }
    }
    /* Check globals */
    for (int i = 0; i < num_symbols; i++) {
        if (strcmp(symbols[i].name, name) == 0) {
            return &symbols[i];
        }
    }
    return NULL;
}

static struct symbol *add_global(const char *name, int type, int data_type, int ptr_level) {
    if (num_symbols >= MAX_SYMBOLS) error("too many symbols");
    struct symbol *sym = &symbols[num_symbols++];
    strncpy(sym->name, name, MAX_IDENT - 1);
    sym->type = type;
    sym->data_type = data_type;
    sym->ptr_level = ptr_level;
    sym->offset = 0;
    sym->size = 0;
    return sym;
}

static struct symbol *add_local(const char *name, int data_type, int ptr_level) {
    if (num_locals >= MAX_LOCALS) error("too many locals");
    struct symbol *sym = &locals[num_locals++];
    strncpy(sym->name, name, MAX_IDENT - 1);
    sym->type = SYM_LOCAL;
    sym->data_type = data_type;
    sym->ptr_level = ptr_level;
    local_offset += SIZE_INT;
    sym->offset = local_offset;
    sym->size = 0;
    return sym;
}

/* ============================================
 * Code Generation - ARM64
 * ============================================ */

static void emit(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(output_file, fmt, ap);
    va_end(ap);
    fprintf(output_file, "\n");
}

static int new_label(void) {
    return label_count++;
}

static void emit_label(int label) {
    fprintf(output_file, "L%d:\n", label);
}

/* Emit function prologue */
static void emit_prologue(const char *name, int local_size) {
    emit(".global _%s", name);
    emit("_%s:", name);
    emit("    stp x29, x30, [sp, #-16]!");
    emit("    mov x29, sp");
    if (local_size > 0) {
        local_size = (local_size + 15) & ~15;  /* Align to 16 */
        emit("    sub sp, sp, #%d", local_size);
    }
}

/* Emit function epilogue */
static void emit_epilogue(int local_size) {
    if (local_size > 0) {
        local_size = (local_size + 15) & ~15;
        emit("    add sp, sp, #%d", local_size);
    }
    emit("    ldp x29, x30, [sp], #16");
    emit("    ret");
}

/* Load value to x0 */
static void emit_load_num(long val) {
    if (val >= 0 && val < 65536) {
        emit("    mov x0, #%ld", val);
    } else if (val < 0 && val >= -65536) {
        emit("    mov x0, #%ld", val);
    } else {
        emit("    mov x0, #%ld", val & 0xFFFF);
        if ((val >> 16) & 0xFFFF)
            emit("    movk x0, #%ld, lsl #16", (val >> 16) & 0xFFFF);
        if ((val >> 32) & 0xFFFF)
            emit("    movk x0, #%ld, lsl #32", (val >> 32) & 0xFFFF);
        if ((val >> 48) & 0xFFFF)
            emit("    movk x0, #%ld, lsl #48", (val >> 48) & 0xFFFF);
    }
}

/* Push x0 to stack */
static void emit_push(void) {
    emit("    str x0, [sp, #-16]!");
}

/* Pop to x1 */
static void emit_pop(void) {
    emit("    ldr x1, [sp], #16");
}

/* Load local variable to x0 */
static void emit_load_local(int offset) {
    emit("    ldr x0, [x29, #-%d]", offset);
}

/* Store x0 to local variable */
static void emit_store_local(int offset) {
    emit("    str x0, [x29, #-%d]", offset);
}

/* Load global variable address to x0 */
static void emit_load_global_addr(const char *name) {
    emit("    adrp x0, _%s@PAGE", name);
    emit("    add x0, x0, _%s@PAGEOFF", name);
}

/* Dereference: x0 = *x0 */
static void emit_deref(int size) {
    if (size == 1) {
        emit("    ldrb w0, [x0]");
    } else {
        emit("    ldr x0, [x0]");
    }
}

/* Store x1 to address in x0 */
static void emit_store_deref(int size) {
    if (size == 1) {
        emit("    strb w1, [x0]");
    } else {
        emit("    str x1, [x0]");
    }
}

/* ============================================
 * Expression Parsing
 * ============================================ */

static void parse_expr(void);
static void parse_assign_expr(void);
static void parse_ternary_expr(void);
static void parse_logical_or_expr(void);
static void parse_logical_and_expr(void);
static void parse_or_expr(void);
static void parse_xor_expr(void);
static void parse_and_expr(void);
static void parse_equality_expr(void);
static void parse_relational_expr(void);
static void parse_shift_expr(void);
static void parse_additive_expr(void);
static void parse_multiplicative_expr(void);
static void parse_unary_expr(void);
static void parse_postfix_expr(void);
static void parse_primary_expr(void);

static void parse_expr(void) {
    parse_assign_expr();
    while (token == TK_COMMA) {
        next_token();
        parse_assign_expr();
    }
}

static void parse_assign_expr(void) {
    /* For simplicity, check if this is an assignment */
    /* A proper implementation would use lvalue tracking */
    parse_ternary_expr();
}

static void parse_ternary_expr(void) {
    parse_logical_or_expr();
    if (token == TK_QUEST) {
        next_token();
        int else_label = new_label();
        int end_label = new_label();
        emit("    cbz x0, L%d", else_label);
        parse_expr();
        expect(TK_COLON);
        emit("    b L%d", end_label);
        emit_label(else_label);
        parse_ternary_expr();
        emit_label(end_label);
    }
}

static void parse_logical_or_expr(void) {
    parse_logical_and_expr();
    while (token == TK_LOR) {
        next_token();
        emit_push();
        parse_logical_and_expr();
        emit_pop();
        emit("    orr x0, x0, x1");
        emit("    cmp x0, #0");
        emit("    cset x0, ne");
    }
}

static void parse_logical_and_expr(void) {
    parse_or_expr();
    while (token == TK_LAND) {
        next_token();
        emit_push();
        parse_or_expr();
        emit_pop();
        emit("    cmp x0, #0");
        emit("    cset x0, ne");
        emit("    cmp x1, #0");
        emit("    cset x1, ne");
        emit("    and x0, x0, x1");
    }
}

static void parse_or_expr(void) {
    parse_xor_expr();
    while (token == TK_OR) {
        next_token();
        emit_push();
        parse_xor_expr();
        emit_pop();
        emit("    orr x0, x0, x1");
    }
}

static void parse_xor_expr(void) {
    parse_and_expr();
    while (token == TK_XOR) {
        next_token();
        emit_push();
        parse_and_expr();
        emit_pop();
        emit("    eor x0, x0, x1");
    }
}

static void parse_and_expr(void) {
    parse_equality_expr();
    while (token == TK_AMP) {
        next_token();
        emit_push();
        parse_equality_expr();
        emit_pop();
        emit("    and x0, x0, x1");
    }
}

static void parse_equality_expr(void) {
    parse_relational_expr();
    while (token == TK_EQ || token == TK_NE) {
        int op = token;
        next_token();
        emit_push();
        parse_relational_expr();
        emit_pop();
        emit("    cmp x1, x0");
        emit("    cset x0, %s", op == TK_EQ ? "eq" : "ne");
    }
}

static void parse_relational_expr(void) {
    parse_shift_expr();
    while (token == TK_LT || token == TK_GT || token == TK_LE || token == TK_GE) {
        int op = token;
        next_token();
        emit_push();
        parse_shift_expr();
        emit_pop();
        emit("    cmp x1, x0");
        const char *cond;
        switch (op) {
            case TK_LT: cond = "lt"; break;
            case TK_GT: cond = "gt"; break;
            case TK_LE: cond = "le"; break;
            default: cond = "ge"; break;
        }
        emit("    cset x0, %s", cond);
    }
}

static void parse_shift_expr(void) {
    parse_additive_expr();
    while (token == TK_LSHIFT || token == TK_RSHIFT) {
        int op = token;
        next_token();
        emit_push();
        parse_additive_expr();
        emit_pop();
        emit("    %s x0, x1, x0", op == TK_LSHIFT ? "lsl" : "asr");
    }
}

static void parse_additive_expr(void) {
    parse_multiplicative_expr();
    while (token == TK_PLUS || token == TK_MINUS) {
        int op = token;
        next_token();
        emit_push();
        parse_multiplicative_expr();
        emit_pop();
        emit("    %s x0, x1, x0", op == TK_PLUS ? "add" : "sub");
    }
}

static void parse_multiplicative_expr(void) {
    parse_unary_expr();
    while (token == TK_STAR || token == TK_SLASH || token == TK_MOD) {
        int op = token;
        next_token();
        emit_push();
        parse_unary_expr();
        emit_pop();
        if (op == TK_STAR) {
            emit("    mul x0, x1, x0");
        } else if (op == TK_SLASH) {
            emit("    sdiv x0, x1, x0");
        } else {
            emit("    sdiv x2, x1, x0");
            emit("    msub x0, x2, x0, x1");
        }
    }
}

static void parse_unary_expr(void) {
    if (token == TK_MINUS) {
        next_token();
        parse_unary_expr();
        emit("    neg x0, x0");
    } else if (token == TK_PLUS) {
        next_token();
        parse_unary_expr();
    } else if (token == TK_LNOT) {
        next_token();
        parse_unary_expr();
        emit("    cmp x0, #0");
        emit("    cset x0, eq");
    } else if (token == TK_TILDE) {
        next_token();
        parse_unary_expr();
        emit("    mvn x0, x0");
    } else if (token == TK_STAR) {
        /* Dereference */
        next_token();
        parse_unary_expr();
        emit_deref(SIZE_INT);
    } else if (token == TK_AMP) {
        /* Address-of */
        next_token();
        if (token != TK_IDENT) error("expected identifier after &");
        struct symbol *sym = find_symbol(token_str);
        if (!sym) error("undefined symbol: %s", token_str);
        if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
            emit("    sub x0, x29, #%d", sym->offset);
        } else {
            emit_load_global_addr(sym->name);
        }
        next_token();
    } else if (token == TK_INC || token == TK_DEC) {
        int op = token;
        next_token();
        if (token != TK_IDENT) error("expected identifier after ++/--");
        struct symbol *sym = find_symbol(token_str);
        if (!sym) error("undefined symbol: %s", token_str);
        if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
            emit_load_local(sym->offset);
            emit("    %s x0, x0, #1", op == TK_INC ? "add" : "sub");
            emit_store_local(sym->offset);
        }
        next_token();
    } else if (token == TK_SIZEOF) {
        next_token();
        expect(TK_LPAREN);
        /* Simplified: just handle basic types */
        if (token == TK_INT) {
            emit_load_num(SIZE_INT);
        } else if (token == TK_CHAR_KW) {
            emit_load_num(SIZE_CHAR);
        } else {
            emit_load_num(SIZE_INT);
        }
        next_token();
        while (token == TK_STAR) next_token();  /* Skip pointer stars */
        expect(TK_RPAREN);
    } else {
        parse_postfix_expr();
    }
}

static void parse_postfix_expr(void) {
    parse_primary_expr();

    while (1) {
        if (token == TK_LBRACKET) {
            /* Array indexing */
            next_token();
            emit_push();
            parse_expr();
            emit("    lsl x0, x0, #3");  /* Assume 8-byte elements */
            emit_pop();
            emit("    add x0, x0, x1");
            emit_deref(SIZE_INT);
            expect(TK_RBRACKET);
        } else if (token == TK_LPAREN) {
            /* Function call - x0 already has the function address or we saved the name */
            error("function call in expression not fully supported");
        } else if (token == TK_INC || token == TK_DEC) {
            /* Post increment/decrement */
            next_token();
            /* Simplified - just add/sub 1 */
        } else {
            break;
        }
    }
}

static void parse_primary_expr(void) {
    if (token == TK_NUM || token == TK_CHAR) {
        emit_load_num(token_val);
        next_token();
    } else if (token == TK_STR) {
        /* String literal */
        int idx = num_strings++;
        string_table[idx] = strdup(token_str);
        emit("    adrp x0, _str%d@PAGE", idx);
        emit("    add x0, x0, _str%d@PAGEOFF", idx);
        next_token();
    } else if (token == TK_IDENT) {
        char name[MAX_IDENT];
        strncpy(name, token_str, MAX_IDENT - 1);
        next_token();

        if (token == TK_LPAREN) {
            /* Function call */
            next_token();
            int argc = 0;
            while (token != TK_RPAREN) {
                if (argc > 0) expect(TK_COMMA);
                parse_assign_expr();
                emit_push();
                argc++;
            }
            expect(TK_RPAREN);

            if (argc > 8) error("more than 8 arguments not supported");

            /* Load arguments into registers x0-x7 */
            for (int i = argc - 1; i >= 0; i--) {
                emit("    ldr x%d, [sp], #16", i);
            }

            emit("    bl _%s", name);
        } else if (token == TK_ASSIGN) {
            /* Assignment */
            next_token();
            struct symbol *sym = find_symbol(name);
            if (!sym) error("undefined symbol: %s", name);

            parse_assign_expr();

            if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
                emit_store_local(sym->offset);
            } else {
                emit("    mov x1, x0");
                emit_load_global_addr(sym->name);
                emit_store_deref(SIZE_INT);
            }
        } else if (token == TK_PLUSEQ || token == TK_MINUSEQ) {
            int op = token;
            next_token();
            struct symbol *sym = find_symbol(name);
            if (!sym) error("undefined symbol: %s", name);

            parse_assign_expr();
            emit_push();

            if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
                emit_load_local(sym->offset);
            } else {
                emit_load_global_addr(sym->name);
                emit_deref(SIZE_INT);
            }

            emit_pop();
            emit("    %s x0, x0, x1", op == TK_PLUSEQ ? "add" : "sub");

            if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
                emit_store_local(sym->offset);
            } else {
                emit("    mov x1, x0");
                emit_load_global_addr(sym->name);
                emit_store_deref(SIZE_INT);
            }
        } else if (token == TK_LBRACKET) {
            /* Array access */
            struct symbol *sym = find_symbol(name);
            if (!sym) error("undefined symbol: %s", name);

            next_token();
            parse_expr();
            emit("    lsl x0, x0, #3");  /* 8-byte elements */
            emit_push();

            if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
                emit("    sub x0, x29, #%d", sym->offset);
            } else {
                emit_load_global_addr(sym->name);
            }

            emit_pop();
            emit("    add x0, x0, x1");

            expect(TK_RBRACKET);

            if (token == TK_ASSIGN) {
                next_token();
                emit_push();  /* Save address */
                parse_assign_expr();
                emit("    mov x1, x0");
                emit_pop();   /* Restore address */
                emit_store_deref(SIZE_INT);
            } else {
                emit_deref(SIZE_INT);
            }
        } else {
            /* Variable reference */
            struct symbol *sym = find_symbol(name);
            if (!sym) error("undefined symbol: %s", name);

            if (sym->type == SYM_LOCAL || sym->type == SYM_PARAM) {
                emit_load_local(sym->offset);
            } else {
                emit_load_global_addr(sym->name);
                emit_deref(SIZE_INT);
            }
        }
    } else if (token == TK_LPAREN) {
        next_token();
        parse_expr();
        expect(TK_RPAREN);
    } else {
        error("unexpected token in expression: %d", token);
    }
}

/* ============================================
 * Statement Parsing
 * ============================================ */

static void parse_stmt(void);
static void parse_block(void);

static void parse_stmt(void) {
    if (token == TK_LBRACE) {
        parse_block();
    } else if (token == TK_IF) {
        next_token();
        expect(TK_LPAREN);
        parse_expr();
        expect(TK_RPAREN);

        int else_label = new_label();
        int end_label = new_label();

        emit("    cbz x0, L%d", else_label);
        parse_stmt();

        if (token == TK_ELSE) {
            emit("    b L%d", end_label);
            emit_label(else_label);
            next_token();
            parse_stmt();
            emit_label(end_label);
        } else {
            emit_label(else_label);
        }
    } else if (token == TK_WHILE) {
        next_token();
        int loop_label = new_label();
        int end_label = new_label();

        int saved_break = current_break_label;
        int saved_continue = current_continue_label;
        current_break_label = end_label;
        current_continue_label = loop_label;

        emit_label(loop_label);
        expect(TK_LPAREN);
        parse_expr();
        expect(TK_RPAREN);
        emit("    cbz x0, L%d", end_label);

        parse_stmt();
        emit("    b L%d", loop_label);
        emit_label(end_label);

        current_break_label = saved_break;
        current_continue_label = saved_continue;
    } else if (token == TK_FOR) {
        next_token();
        expect(TK_LPAREN);

        /* Init */
        if (token != TK_SEMI) parse_expr();
        expect(TK_SEMI);

        int loop_label = new_label();
        int end_label = new_label();
        int continue_label = new_label();

        int saved_break = current_break_label;
        int saved_continue = current_continue_label;
        current_break_label = end_label;
        current_continue_label = continue_label;

        emit_label(loop_label);

        /* Condition */
        if (token != TK_SEMI) {
            parse_expr();
            emit("    cbz x0, L%d", end_label);
        }
        expect(TK_SEMI);

        /* Remember update expression position */
        int update_start = ftell(output_file);
        (void)update_start;  /* For now, simplified - just parse and emit in place */

        /* Update */
        int has_update = (token != TK_RPAREN);
        char update_buf[4096] = "";
        FILE *saved_output = output_file;

        if (has_update) {
            output_file = fmemopen(update_buf, sizeof(update_buf), "w");
            parse_expr();
            fclose(output_file);
            output_file = saved_output;
        }
        expect(TK_RPAREN);

        /* Body */
        parse_stmt();

        /* Update (emit here) */
        emit_label(continue_label);
        if (has_update) {
            fprintf(output_file, "%s", update_buf);
        }

        emit("    b L%d", loop_label);
        emit_label(end_label);

        current_break_label = saved_break;
        current_continue_label = saved_continue;
    } else if (token == TK_RETURN) {
        next_token();
        if (token != TK_SEMI) {
            parse_expr();
        }
        emit_epilogue(current_frame_size);
        expect(TK_SEMI);
    } else if (token == TK_BREAK) {
        next_token();
        if (current_break_label < 0) error("break outside loop");
        emit("    b L%d", current_break_label);
        expect(TK_SEMI);
    } else if (token == TK_CONTINUE) {
        next_token();
        if (current_continue_label < 0) error("continue outside loop");
        emit("    b L%d", current_continue_label);
        expect(TK_SEMI);
    } else if (token == TK_SEMI) {
        /* Empty statement */
        next_token();
    } else if (token == TK_INT || token == TK_CHAR_KW) {
        /* Local variable declaration */
        int data_type = token;
        next_token();

        int ptr_level = 0;
        while (token == TK_STAR) {
            ptr_level++;
            next_token();
        }

        if (token != TK_IDENT) error("expected identifier");
        add_local(token_str, data_type, ptr_level);
        next_token();

        if (token == TK_ASSIGN) {
            next_token();
            parse_expr();
            emit_store_local(locals[num_locals - 1].offset);
        }
        expect(TK_SEMI);
    } else {
        /* Expression statement */
        parse_expr();
        expect(TK_SEMI);
    }
}

static void parse_block(void) {
    expect(TK_LBRACE);
    while (token != TK_RBRACE && token != TK_EOF) {
        parse_stmt();
    }
    expect(TK_RBRACE);
}

/* ============================================
 * Declaration Parsing
 * ============================================ */

static void parse_function(const char *name, int return_type, int ptr_level) {
    add_global(name, SYM_FUNC, return_type, ptr_level);

    /* Parse parameters */
    num_locals = 0;
    local_offset = 0;

    expect(TK_LPAREN);
    int param_count = 0;

    while (token != TK_RPAREN) {
        if (param_count > 0) expect(TK_COMMA);

        int ptype = token;
        if (token != TK_INT && token != TK_CHAR_KW && token != TK_VOID)
            error("expected type");
        next_token();

        int pptr = 0;
        while (token == TK_STAR) {
            pptr++;
            next_token();
        }

        if (token != TK_IDENT) error("expected parameter name");
        struct symbol *param = add_local(token_str, ptype, pptr);
        param->type = SYM_PARAM;
        next_token();
        param_count++;
    }
    expect(TK_RPAREN);

    if (token == TK_SEMI) {
        /* Function declaration only */
        next_token();
        return;
    }

    /* Function body */
    expect(TK_LBRACE);

    /* First pass: count local variables */
    /* For simplicity, we'll emit prologue with estimated size */
    int estimated_locals = MAX_LOCALS * SIZE_INT;  /* Safe upper bound */
    current_frame_size = estimated_locals;

    emit_prologue(name, estimated_locals);

    /* Store parameters from registers to stack */
    if (param_count > 8) error("more than 8 parameters not supported");
    for (int i = 0; i < param_count; i++) {
        emit("    str x%d, [x29, #-%d]", i, locals[i].offset);
    }

    /* Parse body */
    while (token != TK_RBRACE && token != TK_EOF) {
        parse_stmt();
    }
    expect(TK_RBRACE);

    /* Default return */
    emit_load_num(0);
    emit_epilogue(estimated_locals);

    num_locals = 0;
    local_offset = 0;
}

static void parse_global_decl(void) {
    int type = token;
    next_token();

    int ptr_level = 0;
    while (token == TK_STAR) {
        ptr_level++;
        next_token();
    }

    if (token != TK_IDENT) error("expected identifier");
    char name[MAX_IDENT];
    strncpy(name, token_str, MAX_IDENT - 1);
    next_token();

    if (token == TK_LPAREN) {
        /* Function */
        parse_function(name, type, ptr_level);
    } else {
        /* Global variable */
        add_global(name, SYM_GLOBAL, type, ptr_level);

        int size = SIZE_INT;
        if (token == TK_LBRACKET) {
            next_token();
            if (token != TK_NUM) error("expected array size");
            size = token_val * SIZE_INT;
            symbols[num_symbols - 1].size = token_val;
            next_token();
            expect(TK_RBRACKET);
        }

        emit(".data");
        emit(".global _%s", name);
        emit("_%s:", name);
        emit("    .space %d", size);
        emit(".text");

        expect(TK_SEMI);
    }
}

/* ============================================
 * Top Level
 * ============================================ */

static void parse_program(void) {
    emit(".text");
    emit(".align 4");

    while (token != TK_EOF) {
        if (token == TK_INT || token == TK_CHAR_KW || token == TK_VOID) {
            parse_global_decl();
        } else {
            error("unexpected token at top level: %d", token);
        }
    }

    /* Emit string literals */
    if (num_strings > 0) {
        emit(".data");
        for (int i = 0; i < num_strings; i++) {
            emit("_str%d:", i);
            emit("    .asciz \"%s\"", string_table[i]);
        }
    }
}

/* ============================================
 * Main
 * ============================================ */

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s input.c [-o output.s]\n", argv[0]);
        return 1;
    }

    input_filename = argv[1];
    input_file = fopen(input_filename, "r");
    if (!input_file) {
        fprintf(stderr, "Cannot open: %s\n", input_filename);
        return 1;
    }

    /* Determine output file */
    const char *output_filename = "a.s";
    for (int i = 2; i < argc - 1; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            output_filename = argv[i + 1];
            break;
        }
    }

    output_file = fopen(output_filename, "w");
    if (!output_file) {
        fprintf(stderr, "Cannot create: %s\n", output_filename);
        return 1;
    }

    /* Initialize lexer */
    next_char();
    next_token();

    /* Parse program */
    parse_program();

    fclose(input_file);
    fclose(output_file);

    return 0;
}
