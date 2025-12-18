; Stage 1: Minimal Forth - Linux i386
; This is DOCUMENTATION for the hex file - you can verify each encoding
;
; Assemble conceptually, but the real source is stage1.hex
; Each instruction shows: address | hex bytes | assembly | comment
;
; Registers:
;   esi = Forth IP (instruction pointer)
;   ebp = data stack pointer (grows down)
;   esp = return stack (grows down)
;   edi = HERE (dictionary pointer)
;
; Memory map (relative to load address):
;   0x0000-0x0800: Forth primitives (this code)
;   0x0800-0x1000: Built-in word definitions
;   0x1000-0x1100: Variables (LATEST, STATE, BASE, etc.)
;   0x1100-0x1200: Input buffer
;   0x1200-0x8000: Dictionary space
;   0x8000-0xFFFF: Stacks
;
; Entry is at offset 0

; ============================================================================
; INITIALIZATION (offset 0x00)
; ============================================================================

; 0000: 89 E5          mov ebp, esp          ; data stack = current esp
; 0002: 81 ED 00 10    sub ebp, 0x1000       ; move down 4K for data stack
; 0006: 00 00
; 0008: BF 00 12 00 00 mov edi, 0x1200       ; HERE = start of dictionary
; 000D: 31 C0          xor eax, eax
; 000F: A3 00 10 00 00 mov [0x1000], eax     ; LATEST = 0
; 0014: A3 04 10 00 00 mov [0x1004], eax     ; STATE = 0 (interpreting)
; 0019: C7 05 08 10    mov dword [0x1008], 10 ; BASE = 10
;       00 00 0A 00
;       00 00
; 0023: E9 XX XX XX XX jmp _interpreter      ; start interpreting

; ============================================================================
; FORTH PRIMITIVES - Each is a native code word
; ============================================================================

; --- DUP ( x -- x x ) @ 0x0030 ---
; 0030: 8B 45 00       mov eax, [ebp]
; 0033: 83 ED 04       sub ebp, 4
; 0036: 89 45 00       mov [ebp], eax
; 0039: E9 XX XX XX XX jmp _next

; --- DROP ( x -- ) @ 0x0040 ---
; 0040: 83 C5 04       add ebp, 4
; 0043: E9 XX XX XX XX jmp _next

; --- SWAP ( a b -- b a ) @ 0x0050 ---
; 0050: 8B 45 00       mov eax, [ebp]
; 0053: 8B 55 04       mov edx, [ebp+4]
; 0056: 89 55 00       mov [ebp], edx
; 0059: 89 45 04       mov [ebp+4], eax
; 005C: E9 XX XX XX XX jmp _next

; --- OVER ( a b -- a b a ) @ 0x0070 ---
; 0070: 8B 45 04       mov eax, [ebp+4]
; 0073: 83 ED 04       sub ebp, 4
; 0076: 89 45 00       mov [ebp], eax
; 0079: E9 XX XX XX XX jmp _next

; --- + ( a b -- a+b ) @ 0x0080 ---
; 0080: 8B 45 00       mov eax, [ebp]
; 0083: 83 C5 04       add ebp, 4
; 0086: 01 45 00       add [ebp], eax
; 0089: E9 XX XX XX XX jmp _next

; --- - ( a b -- a-b ) @ 0x0090 ---
; 0090: 8B 45 00       mov eax, [ebp]
; 0093: 83 C5 04       add ebp, 4
; 0096: 29 45 00       sub [ebp], eax
; 0099: E9 XX XX XX XX jmp _next

; --- * ( a b -- a*b ) @ 0x00A0 ---
; 00A0: 8B 45 04       mov eax, [ebp+4]
; 00A3: F7 6D 00       imul dword [ebp]
; 00A6: 83 C5 04       add ebp, 4
; 00A9: 89 45 00       mov [ebp], eax
; 00AC: E9 XX XX XX XX jmp _next

; --- / ( a b -- a/b ) @ 0x00C0 ---
; 00C0: 8B 4D 00       mov ecx, [ebp]
; 00C3: 8B 45 04       mov eax, [ebp+4]
; 00C6: 99             cdq
; 00C7: F7 F9          idiv ecx
; 00C9: 83 C5 04       add ebp, 4
; 00CC: 89 45 00       mov [ebp], eax
; 00CF: E9 XX XX XX XX jmp _next

; --- @ ( addr -- x ) @ 0x00E0 ---
; 00E0: 8B 45 00       mov eax, [ebp]
; 00E3: 8B 00          mov eax, [eax]
; 00E5: 89 45 00       mov [ebp], eax
; 00E8: E9 XX XX XX XX jmp _next

; --- ! ( x addr -- ) @ 0x00F0 ---
; 00F0: 8B 45 00       mov eax, [ebp]
; 00F3: 8B 55 04       mov edx, [ebp+4]
; 00F6: 89 10          mov [eax], edx
; 00F8: 83 C5 08       add ebp, 8
; 00FB: E9 XX XX XX XX jmp _next

; --- EMIT ( c -- ) @ 0x0100 ---
; 0100: 8B 45 00       mov eax, [ebp]
; 0103: 83 C5 04       add ebp, 4
; 0106: 50             push eax
; 0107: B8 04 00 00 00 mov eax, 4
; 010C: BB 01 00 00 00 mov ebx, 1
; 0111: 89 E1          mov ecx, esp
; 0113: BA 01 00 00 00 mov edx, 1
; 0118: CD 80          int 0x80
; 011A: 58             pop eax
; 011B: E9 XX XX XX XX jmp _next

; --- KEY ( -- c ) @ 0x0120 ---
; 0120: 83 ED 04       sub ebp, 4
; 0123: C7 45 00 00    mov dword [ebp], 0
;       00 00 00
; 012A: B8 03 00 00 00 mov eax, 3
; 012F: 31 DB          xor ebx, ebx
; 0131: 89 E9          mov ecx, ebp
; 0133: BA 01 00 00 00 mov edx, 1
; 0138: CD 80          int 0x80
; 013A: 85 C0          test eax, eax
; 013C: 75 08          jnz .ok
; 013E: C7 45 00 FF    mov dword [ebp], -1
;       FF FF FF
; 0145: E9 XX XX XX XX jmp _next
; .ok:
; 014A: E9 XX XX XX XX jmp _next

; --- = ( a b -- flag ) @ 0x0150 ---
; 0150: 8B 45 00       mov eax, [ebp]
; 0153: 83 C5 04       add ebp, 4
; 0156: 33 45 00       xor eax, [ebp]
; 0159: 74 05          jz .eq
; 015B: 31 C0          xor eax, eax
; 015D: EB 05          jmp .done
; .eq:
; 015F: B8 FF FF FF FF mov eax, -1
; .done:
; 0164: 89 45 00       mov [ebp], eax
; 0167: E9 XX XX XX XX jmp _next

; --- < ( a b -- flag ) @ 0x0170 ---
; 0170: 8B 45 00       mov eax, [ebp]      ; b
; 0173: 83 C5 04       add ebp, 4
; 0176: 39 45 00       cmp [ebp], eax      ; a < b ?
; 0179: 7C 05          jl .lt
; 017B: 31 C0          xor eax, eax
; 017D: EB 05          jmp .done
; .lt:
; 017F: B8 FF FF FF FF mov eax, -1
; .done:
; 0184: 89 45 00       mov [ebp], eax
; 0187: E9 XX XX XX XX jmp _next

; --- HERE ( -- addr ) @ 0x0190 ---
; 0190: 83 ED 04       sub ebp, 4
; 0193: 89 7D 00       mov [ebp], edi
; 0196: E9 XX XX XX XX jmp _next

; --- EXIT @ 0x01A0 --- (return from colon definition)
; 01A0: 5E             pop esi
; 01A1: AD             lodsd
; 01A2: FF E0          jmp eax

; --- NEXT @ 0x01B0 --- (inner interpreter)
; 01B0: AD             lodsd
; 01B1: FF E0          jmp eax

; ============================================================================
; TEXT INTERPRETER @ 0x0200
; ============================================================================

; _interpreter:
; Read word, look up, execute or parse number

; ... (interpreter code continues)

; ============================================================================
; DICTIONARY STRUCTURE
; ============================================================================
; Each word entry:
;   [4 bytes] link to previous word
;   [1 byte]  name length + flags
;   [n bytes] name (not null terminated)
;   [padding] align to 4 bytes
;   [4 bytes] code field (address of code)
;   [n bytes] parameter field (for colon definitions)
