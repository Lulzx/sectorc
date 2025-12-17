// Stage 1: Minimal Forth Interpreter for ARM64 macOS
// A direct-threaded Forth with ~20 primitive words
//
// Register allocation:
//   x19 = IP (Instruction Pointer) - points to next codeword
//   x20 = W  (Working register) - current word address
//   x21 = RSP (Return Stack Pointer)
//   x22 = HERE (dictionary pointer)
//   x23 = LATEST (pointer to latest word)
//   x24 = STATE (0=interpret, 1=compile)
//   sp  = PSP (Parameter Stack Pointer)
//   x0  = TOS (Top of Stack) for optimization
//
// Dictionary entry format:
//   +0:  link pointer (8 bytes) - points to previous entry
//   +8:  flags + length (1 byte)
//   +9:  name (N bytes, padded to 8-byte boundary)
//   +?:  codeword (8 bytes) - address of code to execute
//   +?:  data/parameter field

.global _main
.align 4

// Constants
.equ F_IMMED,    0x80    // Immediate flag
.equ F_HIDDEN,   0x40    // Hidden flag
.equ F_LENMASK,  0x1F    // Length mask

// macOS syscall numbers
.equ SYS_exit,   1
.equ SYS_read,   3
.equ SYS_write,  4

// Buffer sizes
.equ RETURN_STACK_SIZE, 8192
.equ DATA_SPACE_SIZE,   65536
.equ INPUT_BUFFER_SIZE, 256

// ============================================
// Macros for defining Forth words
// ============================================

.macro NEXT
    ldr     x20, [x19], #8      // W = *IP++
    ldr     x1, [x20]           // Get codeword
    br      x1                  // Jump to code
.endm

.macro PUSHRSP reg
    str     \reg, [x21, #-8]!   // Push to return stack
.endm

.macro POPRSP reg
    ldr     \reg, [x21], #8     // Pop from return stack
.endm

.macro PUSH reg
    str     x0, [sp, #-8]!      // Push TOS to stack
    mov     x0, \reg            // New value becomes TOS
.endm

.macro POP reg
    mov     \reg, x0            // Get TOS
    ldr     x0, [sp], #8        // Pop new TOS
.endm

// ============================================
// Data Section
// ============================================
.data

// State variables
var_STATE:      .quad 0         // 0=interpret, 1=compile
var_HERE:       .quad data_space
var_LATEST:     .quad name_BYE  // Points to last defined word
var_BASE:       .quad 10        // Number base

// Input buffer
input_buffer:   .space INPUT_BUFFER_SIZE
input_ptr:      .quad input_buffer
input_end:      .quad input_buffer

// Return stack
.align 4
return_stack_bottom:
    .space RETURN_STACK_SIZE
return_stack_top:

// Data space (for dictionary growth)
.align 4
data_space:
    .space DATA_SPACE_SIZE

// Word buffer for parsing
word_buffer:    .space 64

// ============================================
// Code Section
// ============================================
.text

// Entry point
_main:
    // Initialize stacks and pointers
    adrp    x21, return_stack_top@PAGE
    add     x21, x21, return_stack_top@PAGEOFF

    adrp    x22, var_HERE@PAGE
    add     x22, x22, var_HERE@PAGEOFF
    ldr     x22, [x22]

    adrp    x23, var_LATEST@PAGE
    add     x23, x23, var_LATEST@PAGEOFF
    ldr     x23, [x23]

    mov     x24, #0             // STATE = interpret

    // Start with QUIT (the main interpreter loop)
    adrp    x19, cold_start@PAGE
    add     x19, x19, cold_start@PAGEOFF
    NEXT

// Cold start - jumps to QUIT
cold_start:
    .quad code_QUIT

// ============================================
// DOCOL - Enter a colon definition
// ============================================
DOCOL:
    PUSHRSP x19                 // Save IP on return stack
    add     x19, x20, #8        // IP = word body (after codeword)
    NEXT

// ============================================
// Primitive Words
// ============================================

// DROP ( a -- )
.align 4
name_DROP:
    .quad 0                     // Link (will be set)
    .byte 4                     // Length
    .ascii "DROP"
    .align 3
code_DROP:
    .quad do_DROP
do_DROP:
    ldr     x0, [sp], #8        // Pop new TOS
    NEXT

// DUP ( a -- a a )
.align 4
name_DUP:
    .quad name_DROP
    .byte 3
    .ascii "DUP"
    .align 3
code_DUP:
    .quad do_DUP
do_DUP:
    str     x0, [sp, #-8]!      // Push TOS
    NEXT

// SWAP ( a b -- b a )
.align 4
name_SWAP:
    .quad name_DUP
    .byte 4
    .ascii "SWAP"
    .align 3
code_SWAP:
    .quad do_SWAP
do_SWAP:
    ldr     x1, [sp]            // Get second
    str     x0, [sp]            // Store first
    mov     x0, x1              // TOS = second
    NEXT

// OVER ( a b -- a b a )
.align 4
name_OVER:
    .quad name_SWAP
    .byte 4
    .ascii "OVER"
    .align 3
code_OVER:
    .quad do_OVER
do_OVER:
    ldr     x1, [sp]            // Get second
    str     x0, [sp, #-8]!      // Push TOS
    mov     x0, x1              // TOS = second (original a)
    NEXT

// ROT ( a b c -- b c a )
.align 4
name_ROT:
    .quad name_OVER
    .byte 3
    .ascii "ROT"
    .align 3
code_ROT:
    .quad do_ROT
do_ROT:
    ldr     x1, [sp]            // b
    ldr     x2, [sp, #8]        // a
    str     x0, [sp, #8]        // c -> where a was
    str     x2, [sp]            // a -> where b was
    mov     x0, x1              // TOS = b
    NEXT

// + ( a b -- a+b )
.align 4
name_PLUS:
    .quad name_ROT
    .byte 1
    .ascii "+"
    .align 3
code_PLUS:
    .quad do_PLUS
do_PLUS:
    ldr     x1, [sp], #8
    add     x0, x1, x0
    NEXT

// - ( a b -- a-b )
.align 4
name_MINUS:
    .quad name_PLUS
    .byte 1
    .ascii "-"
    .align 3
code_MINUS:
    .quad do_MINUS
do_MINUS:
    ldr     x1, [sp], #8
    sub     x0, x1, x0
    NEXT

// * ( a b -- a*b )
.align 4
name_STAR:
    .quad name_MINUS
    .byte 1
    .ascii "*"
    .align 3
code_STAR:
    .quad do_STAR
do_STAR:
    ldr     x1, [sp], #8
    mul     x0, x1, x0
    NEXT

// / ( a b -- a/b )
.align 4
name_SLASH:
    .quad name_STAR
    .byte 1
    .ascii "/"
    .align 3
code_SLASH:
    .quad do_SLASH
do_SLASH:
    ldr     x1, [sp], #8
    sdiv    x0, x1, x0
    NEXT

// MOD ( a b -- a%b )
.align 4
name_MOD:
    .quad name_SLASH
    .byte 3
    .ascii "MOD"
    .align 3
code_MOD:
    .quad do_MOD
do_MOD:
    ldr     x1, [sp], #8
    sdiv    x2, x1, x0
    msub    x0, x2, x0, x1      // x0 = x1 - (x2 * x0) = remainder
    NEXT

// = ( a b -- flag )
.align 4
name_EQU:
    .quad name_MOD
    .byte 1
    .ascii "="
    .align 3
code_EQU:
    .quad do_EQU
do_EQU:
    ldr     x1, [sp], #8
    cmp     x1, x0
    cset    x0, eq
    neg     x0, x0              // Forth true = -1
    NEXT

// < ( a b -- flag )
.align 4
name_LT:
    .quad name_EQU
    .byte 1
    .ascii "<"
    .align 3
code_LT:
    .quad do_LT
do_LT:
    ldr     x1, [sp], #8
    cmp     x1, x0
    cset    x0, lt
    neg     x0, x0
    NEXT

// > ( a b -- flag )
.align 4
name_GT:
    .quad name_LT
    .byte 1
    .ascii ">"
    .align 3
code_GT:
    .quad do_GT
do_GT:
    ldr     x1, [sp], #8
    cmp     x1, x0
    cset    x0, gt
    neg     x0, x0
    NEXT

// AND ( a b -- a&b )
.align 4
name_AND:
    .quad name_GT
    .byte 3
    .ascii "AND"
    .align 3
code_AND:
    .quad do_AND
do_AND:
    ldr     x1, [sp], #8
    and     x0, x1, x0
    NEXT

// OR ( a b -- a|b )
.align 4
name_OR:
    .quad name_AND
    .byte 2
    .ascii "OR"
    .align 3
code_OR:
    .quad do_OR
do_OR:
    ldr     x1, [sp], #8
    orr     x0, x1, x0
    NEXT

// XOR ( a b -- a^b )
.align 4
name_XOR:
    .quad name_OR
    .byte 3
    .ascii "XOR"
    .align 3
code_XOR:
    .quad do_XOR
do_XOR:
    ldr     x1, [sp], #8
    eor     x0, x1, x0
    NEXT

// INVERT ( a -- ~a )
.align 4
name_INVERT:
    .quad name_XOR
    .byte 6
    .ascii "INVERT"
    .align 3
code_INVERT:
    .quad do_INVERT
do_INVERT:
    mvn     x0, x0
    NEXT

// @ ( addr -- value )
.align 4
name_FETCH:
    .quad name_INVERT
    .byte 1
    .ascii "@"
    .align 3
code_FETCH:
    .quad do_FETCH
do_FETCH:
    ldr     x0, [x0]
    NEXT

// ! ( value addr -- )
.align 4
name_STORE:
    .quad name_FETCH
    .byte 1
    .ascii "!"
    .align 3
code_STORE:
    .quad do_STORE
do_STORE:
    ldr     x1, [sp], #8        // value
    str     x1, [x0]            // store
    ldr     x0, [sp], #8        // pop new TOS
    NEXT

// C@ ( addr -- byte )
.align 4
name_CFETCH:
    .quad name_STORE
    .byte 2
    .ascii "C@"
    .align 3
code_CFETCH:
    .quad do_CFETCH
do_CFETCH:
    ldrb    w0, [x0]
    NEXT

// C! ( byte addr -- )
.align 4
name_CSTORE:
    .quad name_CFETCH
    .byte 2
    .ascii "C!"
    .align 3
code_CSTORE:
    .quad do_CSTORE
do_CSTORE:
    ldr     x1, [sp], #8        // byte
    strb    w1, [x0]            // store
    ldr     x0, [sp], #8        // pop new TOS
    NEXT

// >R ( a -- ) (R: -- a )
.align 4
name_TOR:
    .quad name_CSTORE
    .byte 2
    .ascii ">R"
    .align 3
code_TOR:
    .quad do_TOR
do_TOR:
    PUSHRSP x0
    ldr     x0, [sp], #8
    NEXT

// R> ( -- a ) (R: a -- )
.align 4
name_FROMR:
    .quad name_TOR
    .byte 2
    .ascii "R>"
    .align 3
code_FROMR:
    .quad do_FROMR
do_FROMR:
    str     x0, [sp, #-8]!
    POPRSP  x0
    NEXT

// R@ ( -- a ) (R: a -- a )
.align 4
name_RFETCH:
    .quad name_FROMR
    .byte 2
    .ascii "R@"
    .align 3
code_RFETCH:
    .quad do_RFETCH
do_RFETCH:
    str     x0, [sp, #-8]!
    ldr     x0, [x21]
    NEXT

// EMIT ( c -- )
.align 4
name_EMIT:
    .quad name_RFETCH
    .byte 4
    .ascii "EMIT"
    .align 3
code_EMIT:
    .quad do_EMIT
do_EMIT:
    // Write one character to stdout
    str     x0, [sp, #-8]!      // Push char to stack as buffer
    mov     x0, #1              // fd = stdout
    mov     x1, sp              // buf = stack
    mov     x2, #1              // count = 1
    mov     x16, #SYS_write
    svc     #0x80
    add     sp, sp, #8          // Clean up buffer
    ldr     x0, [sp], #8        // Pop new TOS
    NEXT

// KEY ( -- c )
.align 4
name_KEY:
    .quad name_EMIT
    .byte 3
    .ascii "KEY"
    .align 3
code_KEY:
    .quad do_KEY
do_KEY:
    str     x0, [sp, #-8]!      // Push current TOS
    sub     sp, sp, #8          // Allocate buffer
    mov     x0, #0              // fd = stdin
    mov     x1, sp              // buf = stack
    mov     x2, #1              // count = 1
    mov     x16, #SYS_read
    svc     #0x80
    ldrb    w0, [sp]            // Load char read
    add     sp, sp, #8          // Clean up buffer
    NEXT

// EXIT ( -- ) return from word
.align 4
name_EXIT:
    .quad name_KEY
    .byte 4
    .ascii "EXIT"
    .align 3
code_EXIT:
    .quad do_EXIT
do_EXIT:
    POPRSP  x19                 // Pop return address
    NEXT

// LIT ( -- n ) push next cell as literal
.align 4
name_LIT:
    .quad name_EXIT
    .byte 3
    .ascii "LIT"
    .align 3
code_LIT:
    .quad do_LIT
do_LIT:
    str     x0, [sp, #-8]!      // Push current TOS
    ldr     x0, [x19], #8       // Load literal, advance IP
    NEXT

// BRANCH ( -- ) unconditional branch
.align 4
name_BRANCH:
    .quad name_LIT
    .byte 6
    .ascii "BRANCH"
    .align 3
code_BRANCH:
    .quad do_BRANCH
do_BRANCH:
    ldr     x1, [x19]           // Get offset
    add     x19, x19, x1        // IP += offset
    NEXT

// 0BRANCH ( flag -- ) conditional branch
.align 4
name_ZBRANCH:
    .quad name_BRANCH
    .byte 7
    .ascii "0BRANCH"
    .align 3
code_ZBRANCH:
    .quad do_ZBRANCH
do_ZBRANCH:
    cmp     x0, #0
    ldr     x0, [sp], #8        // Pop flag
    b.eq    do_BRANCH           // If zero, branch
    add     x19, x19, #8        // Skip offset
    NEXT

// HERE ( -- addr )
.align 4
name_HERE:
    .quad name_ZBRANCH
    .byte 4
    .ascii "HERE"
    .align 3
code_HERE:
    .quad do_HERE
do_HERE:
    str     x0, [sp, #-8]!
    mov     x0, x22
    NEXT

// LATEST ( -- addr )
.align 4
name_LATEST:
    .quad name_HERE
    .byte 6
    .ascii "LATEST"
    .align 3
code_LATEST:
    .quad do_LATEST
do_LATEST:
    str     x0, [sp, #-8]!
    mov     x0, x23
    NEXT

// STATE ( -- addr )
.align 4
name_STATE:
    .quad name_LATEST
    .byte 5
    .ascii "STATE"
    .align 3
code_STATE:
    .quad do_STATE
do_STATE:
    str     x0, [sp, #-8]!
    adrp    x0, var_STATE@PAGE
    add     x0, x0, var_STATE@PAGEOFF
    NEXT

// BASE ( -- addr )
.align 4
name_BASE:
    .quad name_STATE
    .byte 4
    .ascii "BASE"
    .align 3
code_BASE:
    .quad do_BASE
do_BASE:
    str     x0, [sp, #-8]!
    adrp    x0, var_BASE@PAGE
    add     x0, x0, var_BASE@PAGEOFF
    NEXT

// , ( n -- ) compile cell
.align 4
name_COMMA:
    .quad name_BASE
    .byte 1
    .ascii ","
    .align 3
code_COMMA:
    .quad do_COMMA
do_COMMA:
    str     x0, [x22], #8       // *HERE++ = n
    ldr     x0, [sp], #8
    NEXT

// C, ( c -- ) compile byte
.align 4
name_CCOMMA:
    .quad name_COMMA
    .byte 2
    .ascii "C,"
    .align 3
code_CCOMMA:
    .quad do_CCOMMA
do_CCOMMA:
    strb    w0, [x22], #1       // *HERE++ = c
    ldr     x0, [sp], #8
    NEXT

// EXECUTE ( xt -- ) execute word
.align 4
name_EXECUTE:
    .quad name_CCOMMA
    .byte 7
    .ascii "EXECUTE"
    .align 3
code_EXECUTE:
    .quad do_EXECUTE
do_EXECUTE:
    mov     x20, x0             // W = xt
    ldr     x0, [sp], #8        // Pop new TOS
    ldr     x1, [x20]           // Get codeword
    br      x1                  // Execute

// BYE ( -- ) exit program
.align 4
name_BYE:
    .quad name_EXECUTE
    .byte 3
    .ascii "BYE"
    .align 3
code_BYE:
    .quad do_BYE
do_BYE:
    mov     x0, #0
    mov     x16, #SYS_exit
    svc     #0x80

// ============================================
// QUIT - Main interpreter loop
// ============================================
.align 4
name_QUIT:
    .quad name_BYE
    .byte 4
    .ascii "QUIT"
    .align 3
code_QUIT:
    .quad do_QUIT
do_QUIT:
    // Reset return stack
    adrp    x21, return_stack_top@PAGE
    add     x21, x21, return_stack_top@PAGEOFF
    mov     x24, #0             // STATE = interpret

quit_loop:
    // Print prompt if interpreting
    cbnz    x24, 1f
    mov     x1, #'>'
    strb    w1, [sp, #-8]!
    mov     x0, #1
    mov     x1, sp
    mov     x2, #1
    mov     x16, #SYS_write
    svc     #0x80
    mov     x1, #' '
    strb    w1, [sp]
    mov     x0, #1
    mov     x1, sp
    mov     x2, #1
    mov     x16, #SYS_write
    svc     #0x80
    add     sp, sp, #8

1:  // Read and process words
    bl      read_word
    cbz     x0, quit_loop       // Empty word, try again

    // Try to find word in dictionary
    bl      find_word
    cbnz    x0, found_word

    // Not found - try to parse as number
    bl      parse_number
    cbz     x1, word_not_found  // x1=0 means parse failed

    // It's a number
    cbz     x24, quit_loop      // If interpreting, number is on stack, continue
    // Compiling: emit LIT followed by number
    adrp    x1, code_LIT@PAGE
    add     x1, x1, code_LIT@PAGEOFF
    str     x1, [x22], #8
    str     x0, [x22], #8
    ldr     x0, [sp], #8        // Pop the number we pushed
    b       quit_loop

found_word:
    // x0 = dictionary entry
    // Check if immediate or compiling
    ldrb    w1, [x0, #8]        // flags byte
    tst     w1, #F_IMMED
    b.ne    execute_word        // Immediate: always execute

    cbz     x24, execute_word   // Interpreting: execute

    // Compiling: append to definition
    add     x1, x0, #8          // Point to flags
2:  ldrb    w2, [x1], #1        // Skip name
    and     w2, w2, #F_LENMASK
    add     x1, x1, x2
    add     x1, x1, #7          // Align up
    and     x1, x1, #~7
    str     x1, [x22], #8       // Compile codeword address
    b       quit_loop

execute_word:
    // Find codeword and execute
    add     x20, x0, #8         // Skip link
3:  ldrb    w1, [x20], #1       // Get length
    and     w1, w1, #F_LENMASK
    add     x20, x20, x1        // Skip name
    add     x20, x20, #7        // Align
    and     x20, x20, #~7
    ldr     x1, [x20]           // Get codeword
    br      x1                  // Execute (will NEXT back to quit_loop)

word_not_found:
    // Print error and continue
    adrp    x1, err_msg@PAGE
    add     x1, x1, err_msg@PAGEOFF
    mov     x0, #2              // stderr
    mov     x2, #10             // len
    mov     x16, #SYS_write
    svc     #0x80
    b       quit_loop

// ============================================
// Subroutines
// ============================================

// read_word: Read next word from input
// Returns: x0 = address of word, x1 = length (0 if EOF/empty)
read_word:
    stp     x29, x30, [sp, #-16]!

    // Skip whitespace
1:  bl      read_char
    cmp     w0, #-1
    b.eq    3f                  // EOF
    cmp     w0, #' '
    b.le    1b                  // Skip space, tab, newline

    // Read word into buffer
    adrp    x2, word_buffer@PAGE
    add     x2, x2, word_buffer@PAGEOFF
    mov     x3, x2              // Save start
2:  strb    w0, [x2], #1        // Store char
    bl      read_char
    cmp     w0, #-1
    b.eq    3f
    cmp     w0, #' '
    b.gt    2b                  // Continue if not whitespace

3:  sub     x1, x2, x3          // Length
    mov     x0, x3              // Address
    ldp     x29, x30, [sp], #16
    ret

// read_char: Read one character
// Returns: w0 = char or -1 on EOF
read_char:
    stp     x29, x30, [sp, #-16]!
    sub     sp, sp, #16

    mov     x0, #0              // stdin
    mov     x1, sp
    mov     x2, #1
    mov     x16, #SYS_read
    svc     #0x80

    cmp     x0, #0
    b.le    1f                  // EOF or error
    ldrb    w0, [sp]
    b       2f
1:  mov     w0, #-1
2:  add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// find_word: Find word in dictionary
// Input: x0 = word addr, x1 = length
// Returns: x0 = entry addr or 0 if not found
find_word:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    mov     x19, x0             // Save word addr
    mov     x20, x1             // Save length
    mov     x0, x23             // Start at LATEST

1:  cbz     x0, 3f              // End of dictionary
    ldrb    w1, [x0, #8]        // Get flags+length
    and     w1, w1, #F_LENMASK  // Mask length
    cmp     w1, w20             // Compare length
    b.ne    2f                  // Different length, skip

    // Compare names
    add     x2, x0, #9          // Name in dictionary
    mov     x3, x19             // Word to find
    mov     x4, x20             // Length
4:  cbz     x4, 5f              // All matched
    ldrb    w5, [x2], #1
    ldrb    w6, [x3], #1
    // Case insensitive compare
    orr     w5, w5, #0x20
    orr     w6, w6, #0x20
    cmp     w5, w6
    b.ne    2f                  // Mismatch
    sub     x4, x4, #1
    b       4b

5:  // Found!
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

2:  // Try next entry
    ldr     x0, [x0]            // Follow link
    b       1b

3:  // Not found
    mov     x0, #0
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// parse_number: Parse string as number
// Input: x0 = string addr, x1 = length
// Output: x0 = number (pushed to stack), x1 = 1 if success, 0 if fail
parse_number:
    stp     x29, x30, [sp, #-16]!
    cbz     x1, parse_fail      // Empty string

    mov     x2, x0              // String pointer
    mov     x3, x1              // Length
    mov     x4, #0              // Result
    mov     x5, #0              // Negative flag

    // Check for negative
    ldrb    w6, [x2]
    cmp     w6, #'-'
    b.ne    1f
    mov     x5, #1
    add     x2, x2, #1
    sub     x3, x3, #1
    cbz     x3, parse_fail

1:  // Get base
    adrp    x7, var_BASE@PAGE
    add     x7, x7, var_BASE@PAGEOFF
    ldr     x7, [x7]

2:  cbz     x3, parse_done
    ldrb    w6, [x2], #1

    // Convert digit
    cmp     w6, #'9'
    b.le    3f
    orr     w6, w6, #0x20       // lowercase
    sub     w6, w6, #('a' - 10)
    b       4f
3:  sub     w6, w6, #'0'
4:  // Check valid digit
    cmp     x6, #0
    b.lt    parse_fail
    cmp     x6, x7
    b.ge    parse_fail

    // result = result * base + digit
    mul     x4, x4, x7
    add     x4, x4, x6
    sub     x3, x3, #1
    b       2b

parse_done:
    // Apply sign
    cbz     x5, 5f
    neg     x4, x4
5:  // Push result
    str     x0, [sp, #-8]!      // Save old TOS (from before call)
    mov     x0, x4              // Result is new TOS
    mov     x1, #1              // Success
    ldp     x29, x30, [sp], #16
    ret

parse_fail:
    mov     x1, #0              // Failure
    ldp     x29, x30, [sp], #16
    ret

// Error message
err_msg:
    .ascii "? Unknown\n"
