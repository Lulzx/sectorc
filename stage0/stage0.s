// Stage 0: ARM64 macOS Hex Loader
// Reads ASCII hex pairs from stdin, writes to executable buffer, jumps to it
// Target size: ~512 bytes
//
// Verification: This file should be small enough to audit by hand.
// Each instruction is documented for manual verification.

.global _start
.align 4

// macOS ARM64 syscall numbers (BSD)
.equ SYS_exit,      1
.equ SYS_read,      3
.equ SYS_write,     4
.equ SYS_mmap,      197

// mmap flags
.equ PROT_READ,     0x01
.equ PROT_WRITE,    0x02
.equ PROT_EXEC,     0x04
.equ MAP_PRIVATE,   0x0002
.equ MAP_ANON,      0x1000
.equ MAP_JIT,       0x0800

// File descriptors
.equ STDIN,         0
.equ STDOUT,        1

// Buffer size for code
.equ BUFSIZE,       0x10000     // 64KB

_start:
    // ========================================
    // Step 1: Allocate executable memory via mmap
    // ========================================
    // mmap(NULL, BUFSIZE, PROT_RWX, MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0)
    mov     x0, #0                          // addr = NULL
    mov     x1, #BUFSIZE                    // length = 64KB
    mov     x2, #(PROT_READ | PROT_WRITE | PROT_EXEC)  // prot = RWX
    movz    x3, #(MAP_PRIVATE | MAP_ANON | MAP_JIT)    // flags
    mov     x4, #-1                         // fd = -1
    mov     x5, #0                          // offset = 0
    mov     x16, #SYS_mmap                  // syscall number
    svc     #0x80                           // syscall

    // Check for mmap failure (returns -1 on error)
    cmn     x0, #1
    b.eq    exit_error

    // Save buffer base and write pointer
    mov     x19, x0                         // x19 = buffer base (preserved)
    mov     x20, x0                         // x20 = write pointer (preserved)

    // ========================================
    // Step 2: Main read loop - read hex from stdin
    // ========================================
read_loop:
    // Read one byte from stdin
    bl      read_byte
    cmp     x0, #-1                         // Check for EOF
    b.eq    execute                         // EOF: run the loaded code

    // Skip whitespace (space, tab, newline, carriage return)
    cmp     w0, #' '
    b.eq    read_loop
    cmp     w0, #'\t'
    b.eq    read_loop
    cmp     w0, #'\n'
    b.eq    read_loop
    cmp     w0, #'\r'
    b.eq    read_loop

    // Skip comments (lines starting with ; or #)
    cmp     w0, #';'
    b.eq    skip_line
    cmp     w0, #'#'
    b.eq    skip_line

    // Convert first hex digit
    bl      hex_to_nibble
    lsl     w21, w0, #4                     // High nibble (w21 preserved)

    // Read second hex digit
    bl      read_byte
    cmp     x0, #-1
    b.eq    execute                         // EOF mid-pair: still execute
    bl      hex_to_nibble
    orr     w21, w21, w0                    // Combine nibbles

    // Store byte to buffer
    strb    w21, [x20], #1                  // Store and increment pointer
    b       read_loop

// ========================================
// Skip rest of line (for comments)
// ========================================
skip_line:
    bl      read_byte
    cmp     x0, #-1
    b.eq    execute
    cmp     w0, #'\n'
    b.ne    skip_line
    b       read_loop

// ========================================
// Step 3: Execute the loaded code
// ========================================
execute:
    // Clear instruction cache for the JIT region
    // This is required on ARM64 for self-modifying code
    mov     x0, x19                         // Start address
    mov     x1, x20                         // End address
    bl      clear_cache

    // Jump to loaded code
    // The loaded code can return here by using 'ret' with x30
    mov     x30, x19                        // Set return address to buffer start
    br      x19                             // Branch to buffer

// ========================================
// Subroutine: Read one byte from stdin
// Returns: x0 = byte value, or -1 on EOF
// ========================================
read_byte:
    stp     x29, x30, [sp, #-16]!           // Save frame pointer and return address
    sub     sp, sp, #16                     // Allocate stack space for buffer

    mov     x0, #STDIN                      // fd = stdin
    mov     x1, sp                          // buf = stack
    mov     x2, #1                          // count = 1
    mov     x16, #SYS_read                  // syscall number
    svc     #0x80                           // syscall

    cmp     x0, #0                          // Check bytes read
    b.le    read_eof                        // 0 or negative = EOF/error

    ldrb    w0, [sp]                        // Load byte read
    add     sp, sp, #16                     // Deallocate stack
    ldp     x29, x30, [sp], #16             // Restore registers
    ret

read_eof:
    mov     x0, #-1                         // Return -1 for EOF
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// ========================================
// Subroutine: Convert ASCII hex digit to nibble value
// Input: w0 = ASCII character ('0'-'9', 'A'-'F', 'a'-'f')
// Output: w0 = nibble value (0-15)
// ========================================
hex_to_nibble:
    cmp     w0, #'9'
    b.le    hex_numeric

    // Uppercase or lowercase letter
    orr     w0, w0, #0x20                   // Convert to lowercase
    sub     w0, w0, #('a' - 10)             // 'a' -> 10, 'f' -> 15
    ret

hex_numeric:
    sub     w0, w0, #'0'                    // '0' -> 0, '9' -> 9
    ret

// ========================================
// Subroutine: Clear instruction cache
// Required for ARM64 JIT code
// ========================================
clear_cache:
    // Use sys_icache_invalidate or inline cache maintenance
    // On ARM64, we need to ensure data cache is written back
    // and instruction cache is invalidated

    // Data cache clean by VA to PoU
    dc      cvau, x19
    dsb     ish

    // Instruction cache invalidate by VA to PoU
    ic      ivau, x19
    dsb     ish
    isb
    ret

// ========================================
// Error exit
// ========================================
exit_error:
    mov     x0, #1                          // Exit code 1
    mov     x16, #SYS_exit
    svc     #0x80

// ========================================
// Clean exit (can be called by loaded code)
// ========================================
.global _exit
_exit:
    mov     x16, #SYS_exit
    svc     #0x80
