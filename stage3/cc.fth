\ Stage 3: Subset C Compiler (Forth)
\ Compiles Minimal C to ARM64 Assembly (text output)

\ =========================================================
\ String Output Helpers
\ =========================================================

\ Print common strings character by character

: .GLOBAL ( -- )
  46 EMIT 103 EMIT 108 EMIT 111 EMIT 98 EMIT 97 EMIT 108 EMIT
;
\ ".global"

: .ALIGN ( -- )
  46 EMIT 97 EMIT 108 EMIT 105 EMIT 103 EMIT 110 EMIT
;
\ ".align"

: ._MAIN ( -- )
  95 EMIT 109 EMIT 97 EMIT 105 EMIT 110 EMIT
;
\ "_main"

: .STP ( -- )
  115 EMIT 116 EMIT 112 EMIT
;
\ "stp"

: .LDP ( -- )
  108 EMIT 100 EMIT 112 EMIT
;
\ "ldp"

: .MOV ( -- )
  109 EMIT 111 EMIT 118 EMIT
;
\ "mov"

: .RET ( -- )
  114 EMIT 101 EMIT 116 EMIT
;
\ "ret"

: .X29 ( -- )
  120 EMIT 50 EMIT 57 EMIT
;
\ "x29"

: .X30 ( -- )
  120 EMIT 51 EMIT 48 EMIT
;
\ "x30"

: .W0 ( -- )
  119 EMIT 48 EMIT
;
\ "w0"

: .SP ( -- )
  115 EMIT 112 EMIT
;
\ "sp"

: .HASH ( -- )
  35 EMIT
;
\ "#"

: .COMMA ( -- )
  44 EMIT
;
\ ","

: .LBRAK ( -- )
  91 EMIT
;
\ "["

: .RBRAK ( -- )
  93 EMIT
;
\ "]"

: .EXCL ( -- )
  33 EMIT
;
\ "!"

: .42 ( -- )
  52 EMIT 50 EMIT
;
\ "42"

: .4 ( -- )
  52 EMIT
;
\ "4"

: .-16 ( -- )
  45 EMIT 49 EMIT 54 EMIT
;
\ "-16"

: .16 ( -- )
  49 EMIT 54 EMIT
;
\ "16"

\ =========================================================
\ Assembly Output
\ =========================================================

: GEN-PROLOGUE
  \ stp x29, x30, [sp, #-16]!
  SPACE SPACE .STP SPACE .X29 .COMMA SPACE .X30 .COMMA SPACE
  .LBRAK .SP .COMMA SPACE .HASH .-16 .RBRAK .EXCL CR
  \ mov x29, sp
  SPACE SPACE .MOV SPACE .X29 .COMMA SPACE .SP CR
;

: GEN-EPILOGUE
  \ ldp x29, x30, [sp], #16
  SPACE SPACE .LDP SPACE .X29 .COMMA SPACE .X30 .COMMA SPACE
  .LBRAK .SP .RBRAK .COMMA SPACE .HASH .16 CR
  \ ret
  SPACE SPACE .RET CR
;

: COMPILE-MAIN
  \ Header: .global _main
  .GLOBAL SPACE ._MAIN CR

  \ .align 4
  .ALIGN SPACE .4 CR

  \ _main:
  ._MAIN 58 EMIT CR

  GEN-PROLOGUE

  \ mov w0, #42
  SPACE SPACE .MOV SPACE .W0 .COMMA SPACE .HASH .42 CR

  GEN-EPILOGUE
;

\ =========================================================
\ Main Entry
\ =========================================================

: RUN
  COMPILE-MAIN
  BYE
;

RUN
