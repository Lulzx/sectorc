// Stage 1: Minimal Forth Interpreter for ARM64 macOS
// Designed for W^X (write XOR execute) environments like Apple Silicon.
// Code is in RX region, data in separate RW region passed via x0.

.text
.align 4
.global _main

// Register allocation:
//   x19 = IP (Instruction Pointer)
//   x20 = W (Working register)
//   x21 = RSP (Return Stack Pointer) - in DATA region
//   x22 = HERE (dictionary pointer) - in DATA region
//   x23 = LATEST (pointer to latest word) - can be in CODE or DATA
//   x24 = STATE (0=interpret, 1=compile)
//   x25 = DATA base pointer (received in x0)
//   x27 = PSP (Parameter Stack Pointer) - in DATA region
//   x28 = CODE base pointer (Lbase)
//   sp  = System stack (for function calls only)

_main:
Lbase:
    // For standalone testing, allocate DATA buffer if x0 looks like argc (small number)
    // Stage 0 passes data buffer in x0 which will be a large address
    cmp     x0, #256            // argc would be small
    b.ge    got_data_buffer

    // Allocate data buffer using mmap
    stp     x29, x30, [sp, #-16]!
    mov     x0, #0              // addr = NULL
    mov     x1, #0x10000        // len = 64KB
    mov     x2, #3              // PROT_READ | PROT_WRITE
    mov     x3, #0x1002         // MAP_ANON | MAP_PRIVATE
    mov     x4, #-1             // fd = -1
    mov     x5, #0              // offset = 0
    mov     x16, #197           // SYS_mmap
    svc     #0x80
    ldp     x29, x30, [sp], #16

got_data_buffer:
    // x0 = data buffer address (passed by Stage 0 or allocated above)
    // x28 = code base address
    adr     x28, Lbase
    mov     x25, x0             // DATA base pointer

    // Initialize pointers using DATA region
    // Data layout in x25 region:
    //   +0x0000: var_STATE (8 bytes)
    //   +0x0008: var_HERE (8 bytes) - holds offset into data region
    //   +0x0010: var_BASE (8 bytes)
    //   +0x0018: var_LATEST (8 bytes) - holds offset from Lbase
    //   +0x0020: input_buffer (256 bytes)
    //   +0x0120: word_buffer (64 bytes)
    //   +0x0160: return_stack (8192 bytes)
    //   +0x2160: data_space (up to 0xE000)
    //   +0xE000: param_stack (8192 bytes) - grows downward

    // Initialize STATE = 0
    str     xzr, [x25, #0]

    // Initialize HERE to point to data_space (0x160 + 8192 = 0x2160)
    mov     x0, #0x160
    add     x0, x0, #8192
    str     x0, [x25, #8]

    // Initialize BASE = 10
    mov     x0, #10
    str     x0, [x25, #16]

    // Initialize LATEST to point to name_QUIT (offset from Lbase)
    adr     x0, name_QUIT
    sub     x0, x0, x28
    str     x0, [x25, #24]

    // Set up return stack pointer
    mov     x21, #0x160
    add     x21, x21, #8192
    add     x21, x21, x25

    // Set up parameter stack pointer (top of buffer)
    mov     x27, #0x10000
    add     x27, x27, x25

    // Load initial volatile state into registers
    ldr     x0, [x25, #8]
    add     x22, x25, x0         // x22 = absolute HERE
    
    ldr     x0, [x25, #24]
    add     x23, x28, x0         // x23 = absolute LATEST

    mov     x24, #0             // STATE = interpret

    // Start with QUIT
    adr     x19, cold_start
    b       next_trampoline

// Constants
.equ F_IMMED,    0x80
.equ F_LENMASK,  0x1F
.equ SYS_exit,   1
.equ SYS_read,   3
.equ SYS_write,  4

// Data region offsets
.equ OFF_STATE,  0
.equ OFF_HERE,   8
.equ OFF_BASE,   16
.equ OFF_LATEST, 24
.equ OFF_INPUT,  0x20
.equ OFF_WORD,   0x120
.equ OFF_RSTACK, 0x160

// NEXT: Offset-based threading
next_trampoline:
    ldr     x20, [x19], #8      // Load word offset
    add     x20, x20, x28       // W = Lbase + offset
    ldr     x1, [x20]           // Load codeword offset
    add     x1, x1, x28         // Code address
    br      x1

.macro NEXT
    ldr     x20, [x19], #8
    add     x20, x20, x28
    ldr     x1, [x20]
    add     x1, x1, x28
    br      x1
.endm

.macro PUSHRSP reg
    str     \reg, [x21, #-8]!
.endm

.macro POPRSP reg
    ldr     \reg, [x21], #8
.endm

cold_start:
    .quad code_QUIT - Lbase

// DOCOL - enter a colon definition
// x20 = W = address of code field (already resolved by NEXT)
// Thread starts immediately after the codeword
DOCOL:
    PUSHRSP x19
    add     x19, x20, #8        // IP = code field + 8 = first thread entry
    NEXT

// ============================================ 
// Primitives
// ============================================ 

.align 4
name_DROP:
    .quad 0
    .byte 4, 'D','R','O','P', 0, 0, 0
code_DROP:
    .quad do_DROP - Lbase
do_DROP:
    add     x27, x27, #8
    NEXT

.align 4
name_DUP:
    .quad name_DROP - Lbase
    .byte 3, 'D','U','P', 0, 0, 0, 0
code_DUP:
    .quad do_DUP - Lbase
do_DUP:
    ldr     x0, [x27]
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_SWAP:
    .quad name_DUP - Lbase
    .byte 4, 'S','W','A','P', 0, 0, 0
code_SWAP:
    .quad do_SWAP - Lbase
do_SWAP:
    ldr     x0, [x27]
    ldr     x1, [x27, #8]
    str     x0, [x27, #8]
    str     x1, [x27]
    NEXT

.align 4
name_OVER:
    .quad name_SWAP - Lbase
    .byte 4, 'O','V','E','R', 0, 0, 0
code_OVER:
    .quad do_OVER - Lbase
do_OVER:
    ldr     x0, [x27, #8]
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_PLUS:
    .quad name_OVER - Lbase
    .byte 1, '+', 0, 0, 0, 0, 0, 0
code_PLUS:
    .quad do_PLUS - Lbase
do_PLUS:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    add     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_MINUS:
    .quad name_PLUS - Lbase
    .byte 1, '-', 0, 0, 0, 0, 0, 0
code_MINUS:
    .quad do_MINUS - Lbase
do_MINUS:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    sub     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_STAR:
    .quad name_MINUS - Lbase
    .byte 1, '*', 0, 0, 0, 0, 0, 0
code_STAR:
    .quad do_STAR - Lbase
do_STAR:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    mul     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_EQU:
    .quad name_STAR - Lbase
    .byte 1, '=', 0, 0, 0, 0, 0, 0
code_EQU:
    .quad do_EQU - Lbase
do_EQU:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    cmp     x1, x0
    cset    x0, eq
    neg     x0, x0
    str     x0, [x27]
    NEXT

.align 4
name_AND:
    .quad name_EQU - Lbase
    .byte 3, 'A','N','D', 0, 0, 0, 0
code_AND:
    .quad do_AND - Lbase
do_AND:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    and     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_OR:
    .quad name_AND - Lbase
    .byte 2, 'O','R', 0, 0, 0, 0, 0
code_OR:
    .quad do_OR - Lbase
do_OR:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    orr     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_XOR:
    .quad name_OR - Lbase
    .byte 3, 'X','O','R', 0, 0, 0, 0
code_XOR:
    .quad do_XOR - Lbase
do_XOR:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    eor     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_LSHIFT:
    .quad name_XOR - Lbase
    .byte 6, 'L','S','H','I','F','T', 0
code_LSHIFT:
    .quad do_LSHIFT - Lbase
do_LSHIFT:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    lsl     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_RSHIFT:
    .quad name_LSHIFT - Lbase
    .byte 6, 'R','S','H','I','F','T', 0
code_RSHIFT:
    .quad do_RSHIFT - Lbase
do_RSHIFT:
    ldr     x0, [x27], #8
    ldr     x1, [x27]
    lsr     x1, x1, x0
    str     x1, [x27]
    NEXT

.align 4
name_FETCH:
    .quad name_RSHIFT - Lbase
    .byte 1, '@', 0, 0, 0, 0, 0, 0
code_FETCH:
    .quad do_FETCH - Lbase
do_FETCH:
    ldr     x0, [x27]
    ldr     x0, [x0]
    str     x0, [x27]
    NEXT

.align 4
name_CFETCH:
    .quad name_FETCH - Lbase
    .byte 2, 'C','@', 0, 0, 0, 0, 0
code_CFETCH:
    .quad do_CFETCH - Lbase
do_CFETCH:
    ldr     x0, [x27]
    ldrb    w0, [x0]
    str     x0, [x27]
    NEXT

.align 4
name_STORE:
    .quad name_CFETCH - Lbase
    .byte 1, '!', 0, 0, 0, 0, 0, 0
code_STORE:
    .quad do_STORE - Lbase
do_STORE:
    ldr     x0, [x27], #8
    ldr     x1, [x27], #8
    str     x1, [x0]
    NEXT

.align 4
name_CSTORE:
    .quad name_STORE - Lbase
    .byte 2, 'C','!', 0, 0, 0, 0, 0
code_CSTORE:
    .quad do_CSTORE - Lbase
do_CSTORE:
    ldr     x0, [x27], #8
    ldr     x1, [x27], #8
    strb    w1, [x0]
    NEXT

.align 4
name_TOR:
    .quad name_CSTORE - Lbase
    .byte 2, '>','R', 0, 0, 0, 0, 0
code_TOR:
    .quad do_TOR - Lbase
do_TOR:
    ldr     x0, [x27], #8
    str     x0, [x21, #-8]!
    NEXT

.align 4
name_RFETCH:
    .quad name_TOR - Lbase
    .byte 2, 'R','@', 0, 0, 0, 0, 0
code_RFETCH:
    .quad do_RFETCH - Lbase
do_RFETCH:
    ldr     x0, [x21]
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_FROMR:
    .quad name_RFETCH - Lbase
    .byte 2, 'R','>', 0, 0, 0, 0, 0
code_FROMR:
    .quad do_FROMR - Lbase
do_FROMR:
    ldr     x0, [x21], #8
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_EMIT:
    .quad name_FROMR - Lbase
    .byte 4, 'E','M','I','T', 0, 0, 0
code_EMIT:
    .quad do_EMIT - Lbase
do_EMIT:
    ldr     x0, [x27], #8
    strb    w0, [x25, #OFF_WORD]
    mov     x0, #1
    add     x1, x25, #OFF_WORD
    mov     x2, #1
    mov     x16, #SYS_write
    svc     #0x80
    NEXT

.align 4
name_TYPE:
    .quad name_EMIT - Lbase
    .byte 4, 'T','Y','P','E', 0, 0, 0
code_TYPE:
    .quad do_TYPE - Lbase
do_TYPE:
    ldr     x2, [x27], #8
    ldr     x1, [x27], #8
    mov     x0, #1
    mov     x16, #SYS_write
    svc     #0x80
    NEXT

.align 4
name_KEY:
    .quad name_TYPE - Lbase
    .byte 3, 'K','E','Y', 0, 0, 0, 0
code_KEY:
    .quad do_KEY - Lbase
do_KEY:
    mov     x0, #0
    add     x1, x25, #OFF_WORD
    mov     x2, #1
    mov     x16, #SYS_read
    svc     #0x80
    cmp     x0, #1
    b.eq    1f
    mov     x0, #-1
    b       2f
1:
    ldrb    w0, [x25, #OFF_WORD]
2:
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_LIT:
    .quad name_KEY - Lbase
    .byte 3, 'L','I','T', 0, 0, 0, 0
code_LIT:
    .quad do_LIT - Lbase
do_LIT:
    ldr     x0, [x19], #8
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_LITERAL:
    .quad name_LIT - Lbase
    .byte 7 | F_IMMED, 'L','I','T','E','R','A','L'
code_LITERAL:
    .quad do_LITERAL - Lbase
do_LITERAL:
    // Compile a literal from stack into the current definition:
    //   ['] LIT ,  (emit LIT)
    //   ,          (emit value)
    ldr     x0, [x27], #8
    adr     x1, code_LIT
    sub     x1, x1, x28
    str     x1, [x22], #8
    str     x0, [x22], #8
    sub     x0, x22, x25
    str     x0, [x25, #OFF_HERE]
    NEXT

.align 4
name_EXIT:
    .quad name_LITERAL - Lbase
    .byte 4, 'E','X','I','T', 0, 0, 0
code_EXIT:
    .quad do_EXIT - Lbase
do_EXIT:
    POPRSP  x19
    NEXT

.align 4
name_BRANCH:
    .quad name_EXIT - Lbase
    .byte 6, 'B','R','A','N','C','H', 0
code_BRANCH:
    .quad do_BRANCH - Lbase
do_BRANCH:
    ldr     x1, [x19]
    add     x19, x19, x1
    NEXT

.align 4
name_0BRANCH:
    .quad name_BRANCH - Lbase
    .byte 7, '0','B','R','A','N','C','H'
code_0BRANCH:
    .quad do_0BRANCH - Lbase
do_0BRANCH:
    ldr     x0, [x27], #8
    cmp     x0, #0
    b.eq    do_BRANCH
    add     x19, x19, #8
    NEXT

.align 4
name_HERE:
    .quad name_0BRANCH - Lbase
    .byte 4, 'H','E','R','E', 0, 0, 0
code_HERE:
    .quad do_HERE - Lbase
do_HERE:
    str     x22, [x27, #-8]!
    NEXT

.align 4
name_COMMA:
    .quad name_HERE - Lbase
    .byte 1, ',', 0, 0, 0, 0, 0, 0
code_COMMA:
    .quad do_COMMA - Lbase
do_COMMA:
    ldr     x0, [x27], #8
    str     x0, [x22], #8
    sub     x0, x22, x25
    str     x0, [x25, #OFF_HERE]
    NEXT

.align 4
name_ALLOT:
    .quad name_COMMA - Lbase
    .byte 5, 'A','L','L','O','T', 0, 0
code_ALLOT:
    .quad do_ALLOT - Lbase
do_ALLOT:
    ldr     x0, [x27], #8
    add     x22, x22, x0
    sub     x0, x22, x25
    str     x0, [x25, #OFF_HERE]
    NEXT

.align 4
name_STATE:
    .quad name_ALLOT - Lbase
    .byte 5, 'S','T','A','T','E', 0, 0
code_STATE:
    .quad do_STATE - Lbase
do_STATE:
    add     x0, x25, #OFF_STATE
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_LATEST:
    .quad name_STATE - Lbase
    .byte 6, 'L','A','T','E','S','T', 0
code_LATEST:
    .quad do_LATEST - Lbase
do_LATEST:
    add     x0, x25, #OFF_LATEST
    str     x0, [x27, #-8]!
    NEXT

.align 4
name_IMMEDIATE:
    .quad name_LATEST - Lbase
    .byte 9, 'I','M','M','E','D','I','A','T','E', 0, 0, 0, 0, 0, 0
code_IMMEDIATE:
    .quad do_IMMEDIATE - Lbase
do_IMMEDIATE:
    ldrb    w0, [x23, #8]
    orr     w0, w0, #F_IMMED
    strb    w0, [x23, #8]
    NEXT

.align 4
name_LBRACKET:
    .quad name_IMMEDIATE - Lbase
    .byte 1 | F_IMMED, '[', 0, 0, 0, 0, 0, 0
code_LBRACKET:
    .quad do_LBRACKET - Lbase
do_LBRACKET:
    mov     x24, #0
    str     x24, [x25, #OFF_STATE]
    NEXT

.align 4
name_RBRACKET:
    .quad name_LBRACKET - Lbase
    .byte 1, ']', 0, 0, 0, 0, 0, 0
code_RBRACKET:
    .quad do_RBRACKET - Lbase
do_RBRACKET:
    mov     x24, #1
    str     x24, [x25, #OFF_STATE]
    NEXT

.align 4
name_COLON:
    .quad name_RBRACKET - Lbase
    .byte 1, ':', 0, 0, 0, 0, 0, 0
code_COLON:
    .quad do_COLON - Lbase
do_COLON:
    bl      read_word
    mov     x2, x22
    sub     x3, x23, x28
    str     x3, [x22], #8
    mov     x23, x2
    sub     x3, x23, x28
    str     x3, [x25, #OFF_LATEST]
    strb    w1, [x22], #1
1:  cbz     x1, 2f
    ldrb    w3, [x0], #1
    strb    w3, [x22], #1
    sub     x1, x1, #1
    b       1b
2:  add     x22, x22, #7
    and     x22, x22, #~7
    adr     x1, DOCOL
    sub     x1, x1, x28
    str     x1, [x22], #8
    sub     x0, x22, x25
    str     x0, [x25, #OFF_HERE]
    mov     x24, #1
    str     x24, [x25, #OFF_STATE]
    NEXT

.align 4
name_SEMICOLON:
    .quad name_COLON - Lbase
    .byte 1 | F_IMMED, ';', 0, 0, 0, 0, 0, 0
code_SEMICOLON:
    .quad do_SEMICOLON - Lbase
do_SEMICOLON:
    adr     x1, code_EXIT       // Compile code field offset, not name
    sub     x1, x1, x28
    str     x1, [x22], #8
    sub     x0, x22, x25
    str     x0, [x25, #OFF_HERE]
    mov     x24, #0
    str     x24, [x25, #OFF_STATE]
    NEXT

.align 4
name_BYE:
    .quad name_SEMICOLON - Lbase
    .byte 3, 'B','Y','E', 0, 0, 0, 0
code_BYE:
    .quad do_BYE - Lbase
do_BYE:
    mov     x0, #0
    mov     x16, #SYS_exit
    svc     #0x80

.align 4
name_TICK:
    .quad name_BYE - Lbase
    .byte 1, '\'', 0, 0, 0, 0, 0, 0
code_TICK:
    .quad do_TICK - Lbase
do_TICK:
    bl      read_word
    bl      find_word
    cbz     x0, 1f
    // Convert name header -> code field address (execution token)
    // code = align8(name + 8 + 1 + len)
    add     x1, x0, #8
    ldrb    w2, [x1], #1
    and     w2, w2, #F_LENMASK
    add     x1, x1, x2
    add     x1, x1, #7
    and     x1, x1, #~7
    sub     x0, x1, x28
    str     x0, [x27, #-8]!
    b       2f
1:  // Unknown word -> push 0
    mov     x0, #0
    str     x0, [x27, #-8]!
2:
    NEXT

.align 4
name_EXECUTE:
    .quad name_TICK - Lbase
    .byte 7, 'E','X','E','C','U','T','E'
code_EXECUTE:
    .quad do_EXECUTE - Lbase
do_EXECUTE:
    ldr     x0, [x27], #8      // xt (code field offset)
    add     x20, x28, x0       // W = Lbase + xt
    ldr     x1, [x20]          // codeword offset
    add     x1, x1, x28        // code address
    br      x1

.align 4
name_BACKSLASH:
    .quad name_EXECUTE - Lbase
    .byte 1 | F_IMMED, '\\', 0, 0, 0, 0, 0, 0
code_BACKSLASH:
    .quad do_BACKSLASH - Lbase
do_BACKSLASH:
1:  bl      read_char
    cmp     w0, #0xA // Newline character
    b.eq    2f
    cmp     w0, #-1
    b.eq    2f
    b       1b
2:  NEXT

.align 4
name_PAREN:
    .quad name_BACKSLASH - Lbase
    .byte 1 | F_IMMED, '(', 0, 0, 0, 0, 0, 0
code_PAREN:
    .quad do_PAREN - Lbase
do_PAREN:
1:  bl      read_char
    cmp     w0, #')'
    b.eq    2f
    cmp     w0, #-1
    b.eq    2f
    b       1b
2:  NEXT

.align 4
xt_STOP:
    .quad code_STOP - Lbase      // Must be code field offset, not name

.align 4
name_STOP:
    .quad name_PAREN - Lbase
    .byte 4, 'S','T','O','P', 0, 0, 0
code_STOP:
    .quad do_STOP - Lbase
do_STOP:
    b       quit_loop

.align 4
name_QUIT:
    .quad name_STOP - Lbase
    .byte 4, 'Q','U','I','T', 0, 0, 0
code_QUIT:
    .quad do_QUIT - Lbase
do_QUIT:
    mov     x21, #0x160
    add     x21, x21, #8192
    add     x21, x21, x25
    mov     x24, #0
    str     x24, [x25, #OFF_STATE]

quit_loop:
    bl      read_word
    cbz     x1, quit_loop

    bl      find_word
    cbnz    x0, found_word

    mov     x0, x1
    mov     x1, x2
    bl      parse_number
    cbz     x1, word_not_found

    ldr     x24, [x25, #OFF_STATE]
    cbz     x24, quit_loop
    adr     x1, code_LIT        // Compile code field offset, not name
    sub     x1, x1, x28
    str     x1, [x22], #8
    ldr     x0, [x27], #8
    str     x0, [x22], #8
    b       quit_loop

found_word:
    ldrb    w1, [x0, #8]
    tst     w1, #F_IMMED
    b.ne    execute_word

    ldr     x24, [x25, #OFF_STATE]
    cbz     x24, execute_word

    // Navigate from name header to code field
    // x0 = name header address
    add     x1, x0, #8          // Skip link
    ldrb    w2, [x1], #1        // Load length byte
    and     w2, w2, #F_LENMASK
    add     x1, x1, x2          // Skip name
    add     x1, x1, #7          // Align to 8 bytes
    and     x1, x1, #~7
    // x1 = code field address
    sub     x1, x1, x28         // Convert to offset
    str     x1, [x22], #8
    b       quit_loop

execute_word:
    adr     x19, xt_STOP
    add     x20, x0, #8
    ldrb    w1, [x20], #1
    and     w1, w1, #F_LENMASK
    add     x20, x20, x1
    add     x20, x20, #7
    and     x20, x20, #~7
    ldr     x1, [x20]
    add     x1, x1, x28
    br      x1

word_not_found:
    adr     x1, err_msg
    mov     x0, #2
    mov     x2, #2
    mov     x16, #SYS_write
    svc     #0x80
    b       quit_loop

// Helpers
read_word:
    stp     x29, x30, [sp, #-16]!
    stp     x9, x10, [sp, #-16]!
    add     x9, x25, #OFF_WORD
    mov     x10, x9
1:  bl      read_char
    cmp     w0, #-1
    b.eq    3f
    cmp     w0, #' '
    b.le    1b
2:  strb    w0, [x9], #1
    bl      read_char
    cmp     w0, #-1
    b.eq    3f
    cmp     w0, #' '
    b.gt    2b
3:  sub     x1, x9, x10
    mov     x0, x10
    ldp     x9, x10, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

read_char:
    stp     x29, x30, [sp, #-16]!
    sub     sp, sp, #16
    mov     x0, #0
    mov     x1, sp
    mov     x2, #1
    mov     x16, #SYS_read
    svc     #0x80
    cmp     x0, #0
    b.le    1f
    ldrb    w0, [sp]
    b       2f
1:  mov     w0, #-1
2:  add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

find_word:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    mov     x19, x0
    mov     x20, x1
    mov     x0, x23
1:  cbz     x0, 3f
    ldr     x1, [x0]
    cbz     x1, check_word
    add     x1, x1, x28
    b       check_link_done
check_word:
    mov     x1, #0
check_link_done:
    ldrb    w2, [x0, #8]
    and     w2, w2, #F_LENMASK
    cmp     w2, w20
    b.ne    2f
    add     x3, x0, #9
    mov     x4, x19
    mov     x5, x20
4:  cbz     x5, 5f
    ldrb    w6, [x3], #1
    ldrb    w7, [x4], #1
    orr     w6, w6, #0x20
    orr     w7, w7, #0x20
    cmp     w6, w7
    b.ne    2f
    sub     x5, x5, #1
    b       4b
5:  ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret
2:  mov     x0, x1
    b       1b
3:  mov     x1, x19
    mov     x2, x20
    mov     x0, #0
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

parse_number:
    str     x30, [x21, #-8]!
    cbz     x1, parse_fail
    mov     x2, x0
    mov     x3, x1
    mov     x4, #0
    mov     x5, #0
    ldrb    w6, [x2]
    cmp     w6, #'-'
    b.ne    1f
    mov     x5, #1
    add     x2, x2, #1
    sub     x3, x3, #1
    cbz     x3, parse_fail
1:  ldr     x7, [x25, #16]
2:  cbz     x3, parse_done
    ldrb    w6, [x2], #1
    cmp     w6, #'9'
    b.le    3f
    orr     w6, w6, #0x20
    sub     w6, w6, #('a' - 10)
    b       4f
3:  sub     w6, w6, #'0'
4:  cmp     x6, #0
    b.lt    parse_fail
    cmp     x6, x7
    b.ge    parse_fail
    mul     x4, x4, x7
    add     x4, x4, x6
    sub     x3, x3, #1
    b       2b
parse_done:
    cbz     x5, 5f
    neg     x4, x4
5:  str     x4, [x27, #-8]!
    mov     x0, x4
    mov     x1, #1
    ldr     x30, [x21], #8
    ret
parse_fail:
    mov     x1, #0
    ldr     x30, [x21], #8
    ret

err_msg: .ascii "?\n"
