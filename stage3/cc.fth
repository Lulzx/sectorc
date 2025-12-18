\ Stage 3: Subset C Compiler (Forth)
\ Reads C source from stdin and emits ARM64 macOS assembly to stdout.
\ Subset target (enough for `tests/stage3/*.c`):
\   - Functions (int return), int parameters, calls, recursion
\   - Locals: int, int*, int[N]
\   - Statements: {}, return, if/else, while, for, expression statements
\   - Expressions: =, + - * / %, == != < <= > >=, unary - & *, indexing []

\ =========================================================
\ Core helpers
\ =========================================================

: 0= ( x -- f ) 0 = ;
: 0<> ( x -- f ) 0= 0= ;
: NEGATE ( x -- -x ) 0 SWAP - ;
: 1+ ( x -- x+1 ) 1 + ;
: 1- ( x -- x-1 ) 1 - ;

\ Comparisons (Stage 1 has = but no < / >)
: <  ( a b -- f ) - 63 RSHIFT NEGATE ; \ true=-1, false=0
: >  ( a b -- f ) SWAP < ;
: <= ( a b -- f ) > 0= ;
: >= ( a b -- f ) < 0= ;

: ALIGN8 ( n -- n' ) 7 + -8 AND ;

\ Byte copy: ( src dst len -- )
: CMOVE
  BEGIN
    DUP 0= IF DROP 2DROP EXIT THEN
    >R
    OVER C@ OVER C!
    1+ SWAP 1+ SWAP
    R> 1-
  AGAIN
;

\ =========================================================
\ Base addresses / cell indexing (use Stage1 input_buffer area as cells)
\ =========================================================

: CCBASE ( -- addr ) STATE 32 + ; \ DATA + 0x20
: CCELL  ( i -- addr ) 3 LSHIFT CCBASE + ; \ i*8 + base

\ Cell map (all are addresses of 8-byte cells unless noted)
: UNGET-COUNT  0 CCELL ;
: UNGET0       1 CCELL ;
: UNGET1       2 CCELL ;

: TOK          3 CCELL ; \ kind
: TOKVAL       4 CCELL ; \ number value
: TOKLEN       5 CCELL ; \ identifier length

: FNPTR        6 CCELL ; \ -> fn name buffer
: FNLEN        7 CCELL ;

: CALLPTR      8 CCELL ; \ -> call/identifier temp buffer
: CALLLEN      9 CCELL ;

: IDPTR       10 CCELL ; \ -> identifier buffer

: EXPRXT      11 CCELL ; \ xt for EXPR
: STMTXT      12 CCELL ; \ xt for STMT

: SYMCOUNT    13 CCELL ;
: LOCOFF      14 CCELL ;
: RETLBL      15 CCELL ;
: LBLCOUNT    16 CCELL ;

: SRCMODE     17 CCELL ; \ 0=stdin, 1=replay
: TBUFN       18 CCELL ;
: TBIDX       19 CCELL ;

: SYMTABPTR   20 CCELL ;
: TBUFPTR     21 CCELL ;
: SAVTOKPTR   22 CCELL ;
: CALLEEPTR   23 CCELL ; \ -> callee name buffer (function calls)
: CALLEELEN   24 CCELL ;

: FNBUF   ( -- addr ) FNPTR @ ;
: CALLBUF ( -- addr ) CALLPTR @ ;
: IDBUF   ( -- addr ) IDPTR @ ;
: CALLEEBUF ( -- addr ) CALLEEPTR @ ;

\ =========================================================
\ Error handling
\ =========================================================

: FAIL ( -- )
  69 EMIT 82 EMIT 82 EMIT 10 EMIT \ "ERR\n"
  BYE
;

\ =========================================================
\ Character classes
\ =========================================================

: EOF? ( c -- f ) -1 = ;
: WS?  ( c -- f ) DUP EOF? IF DROP 0 EXIT THEN 32 <= ;

: UPPER? ( c -- f ) DUP 65 >= SWAP 90 <= AND ;
: LOWER? ( c -- f ) DUP 97 >= SWAP 122 <= AND ;
: UNDER? ( c -- f ) 95 = ;

: ALPHA? ( c -- f )
  DUP UPPER? >R
  DUP LOWER? R> OR
  SWAP UNDER? OR
;

: DIGIT? ( c -- f ) DUP 48 >= SWAP 57 <= AND ;
: ALNUM? ( c -- f ) DUP ALPHA? SWAP DIGIT? OR ;

: TOLOWER ( c -- c )
  DUP UPPER? IF 32 OR THEN
;

\ =========================================================
\ Token kinds
\ =========================================================

: TK_ID     ( -- n ) 256 ;
: TK_NUM    ( -- n ) 257 ;
: KW_INT    ( -- n ) 258 ;
: KW_RETURN ( -- n ) 259 ;
: KW_IF     ( -- n ) 260 ;
: KW_ELSE   ( -- n ) 261 ;
: KW_WHILE  ( -- n ) 262 ;
: KW_FOR    ( -- n ) 263 ;

: TK_EQEQ   ( -- n ) 300 ;
: TK_NEQ    ( -- n ) 301 ;
: TK_LE     ( -- n ) 302 ;
: TK_GE     ( -- n ) 303 ;

\ =========================================================
\ Lexer
\ =========================================================

: GETC ( -- c )
  UNGET-COUNT @ DUP 0= IF DROP KEY EXIT THEN
  DUP 1 = IF DROP UNGET0 @ 0 UNGET-COUNT ! EXIT THEN
  DROP UNGET1 @ 1 UNGET-COUNT !
;

: UNGETC ( c -- )
  UNGET-COUNT @ DUP 0= IF DROP UNGET0 ! 1 UNGET-COUNT ! EXIT THEN
  DUP 1 = IF DROP UNGET1 ! 2 UNGET-COUNT ! EXIT THEN
  DROP
;

: EOL? ( c -- f ) DUP 10 = SWAP 13 = OR ;

: SKIP-LINE ( -- )
  BEGIN
    GETC DUP EOF? IF DROP EXIT THEN
    DUP EOL? IF DROP EXIT THEN
    DROP
  AGAIN
;

: SKIP-BLOCK ( -- )
  BEGIN
    GETC DUP EOF? IF DROP EXIT THEN
    DUP 42 = IF \ '*'
      DROP
      GETC DUP EOF? IF DROP EXIT THEN
      DUP 47 = IF DROP EXIT THEN \ '/'
      UNGETC
    ELSE
      DROP
    THEN
  AGAIN
;

: SKIP-WS ( -- )
  BEGIN
    GETC DUP EOF? IF UNGETC EXIT THEN
    DUP WS? IF DROP
    ELSE DUP 47 = IF \ '/'
      DROP
      GETC DUP EOF? IF UNGETC 47 UNGETC EXIT THEN
      DUP 47 = IF DROP SKIP-LINE
      ELSE DUP 42 = IF DROP SKIP-BLOCK
      ELSE
        UNGETC 47 UNGETC
        EXIT
      THEN THEN
    ELSE
      UNGETC
      EXIT
    THEN THEN
  AGAIN
;

: ID@ ( i -- c ) IDBUF + C@ ;

: STORE-ID ( idx c -- idx' )
  TOLOWER
  SWAP DUP >R
  IDBUF +
  C!
  R> 1+
;

: READIDENT ( c -- len )
  0 SWAP STORE-ID
  BEGIN
    GETC DUP ALNUM? IF
      STORE-ID
    ELSE
      UNGETC
      EXIT
    THEN
  AGAIN
;

: DIGITVAL ( c -- n ) 48 - ;

: READNUM ( c -- n )
  DIGITVAL
  BEGIN
    GETC DUP DIGIT? IF
      DIGITVAL >R 10 * R> +
    ELSE
      UNGETC
      EXIT
    THEN
  AGAIN
;

: IS-INT? ( -- f )
  TOKLEN @ 3 =
  0 ID@ 105 = AND
  1 ID@ 110 = AND
  2 ID@ 116 = AND
;

: IS-RETURN? ( -- f )
  TOKLEN @ 6 =
  0 ID@ 114 = AND
  1 ID@ 101 = AND
  2 ID@ 116 = AND
  3 ID@ 117 = AND
  4 ID@ 114 = AND
  5 ID@ 110 = AND
;

: IS-IF? ( -- f )
  TOKLEN @ 2 =
  0 ID@ 105 = AND
  1 ID@ 102 = AND
;

: IS-ELSE? ( -- f )
  TOKLEN @ 4 =
  0 ID@ 101 = AND
  1 ID@ 108 = AND
  2 ID@ 115 = AND
  3 ID@ 101 = AND
;

: IS-WHILE? ( -- f )
  TOKLEN @ 5 =
  0 ID@ 119 = AND
  1 ID@ 104 = AND
  2 ID@ 105 = AND
  3 ID@ 108 = AND
  4 ID@ 101 = AND
;

: IS-FOR? ( -- f )
  TOKLEN @ 3 =
  0 ID@ 102 = AND
  1 ID@ 111 = AND
  2 ID@ 114 = AND
;

\ Token record helpers (56-byte records)
: REC-VAL  ( rec -- addr ) 8 + ;
: REC-LEN  ( rec -- addr ) 16 + ;
: REC-NAME ( rec -- addr ) 24 + ;

: TBUF-REC ( i -- rec ) 56 * TBUFPTR @ + ;

: REPLAY-NEXT ( -- )
  TBIDX @ TBUFN @ = IF
    0 TOK ! 0 TOKVAL ! 0 TOKLEN ! EXIT
  THEN
  TBIDX @ TBUF-REC >R
  R@ @ TOK !
  R@ REC-VAL @ TOKVAL !
  R@ REC-LEN @ TOKLEN !
  R@ REC-NAME IDBUF 32 CMOVE
  R> DROP
  TBIDX @ 1+ TBIDX !
;

: NEXTTOK ( -- )
  SRCMODE @ 0<> IF REPLAY-NEXT EXIT THEN

  SKIP-WS
  GETC DUP EOF? IF DROP 0 TOK ! 0 TOKVAL ! 0 TOKLEN ! EXIT THEN

  DUP ALPHA? IF
    READIDENT TOKLEN !
    0 TOKVAL !
    IS-INT? IF KW_INT TOK ! EXIT THEN
    IS-RETURN? IF KW_RETURN TOK ! EXIT THEN
    IS-IF? IF KW_IF TOK ! EXIT THEN
    IS-ELSE? IF KW_ELSE TOK ! EXIT THEN
    IS-WHILE? IF KW_WHILE TOK ! EXIT THEN
    IS-FOR? IF KW_FOR TOK ! EXIT THEN
    TK_ID TOK ! EXIT
  THEN

  DUP DIGIT? IF
    READNUM TOKVAL !
    0 TOKLEN !
    TK_NUM TOK ! EXIT
  THEN

  0 TOKVAL ! 0 TOKLEN !

  \ operators with lookahead
  DUP 61 = IF \ '='
    DROP GETC DUP 61 = IF DROP TK_EQEQ TOK ! EXIT THEN
    UNGETC 61 TOK ! EXIT
  THEN

  DUP 33 = IF \ '!'
    DROP GETC DUP 61 = IF DROP TK_NEQ TOK ! EXIT THEN
    FAIL
  THEN

  DUP 60 = IF \ '<'
    DROP GETC DUP 61 = IF DROP TK_LE TOK ! EXIT THEN
    UNGETC 60 TOK ! EXIT
  THEN

  DUP 62 = IF \ '>'
    DROP GETC DUP 61 = IF DROP TK_GE TOK ! EXIT THEN
    UNGETC 62 TOK ! EXIT
  THEN

  \ single-char token
  TOK !
;

\ =========================================================
\ Parser helpers
\ =========================================================

: EXPECT0 ( kind -- )
  TOK @ = 0= IF FAIL THEN
;

: EXPECT ( kind -- )
  EXPECT0
  NEXTTOK
;

: SAVE-ID ( -- )
  TOKLEN @ CALLLEN !
  IDBUF CALLBUF CALLLEN @ CMOVE
;

: SAVE-CALLEE ( -- )
  CALLLEN @ CALLEELEN !
  CALLBUF CALLEEBUF CALLEELEN @ CMOVE
;

: EXPECT-ID ( -- )
  TOK @ TK_ID = 0= IF FAIL THEN
  SAVE-ID
  NEXTTOK
;

: EXPECT-NUM ( -- n )
  TOK @ TK_NUM = 0= IF FAIL THEN
  TOKVAL @
  NEXTTOK
;

\ =========================================================
\ Symbol table (per-function)
\ =========================================================

\ Symbol record layout (56 bytes):
\   +0  off (cell)
\   +8  type (cell): 0=int, 1=int*, 2=int[N]
\  +16 aux (cell): array element count, else 0
\  +24 name bytes: [len][chars...]

: SYM-REC ( i -- rec ) 56 * SYMTABPTR @ + ;

: SYM-INIT ( -- )
  0 SYMCOUNT !
  0 LOCOFF !
;

: STR= ( a b len -- f )
  BEGIN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    >R
    OVER C@ OVER C@ = 0= IF R> DROP 2DROP 0 EXIT THEN
    1+ SWAP 1+ SWAP
    R> 1-
  AGAIN
;

: SYM-FIND ( -- idx|-1 )
  SYMCOUNT @ 0 \ count idx
  BEGIN
    OVER 0= IF 2DROP -1 EXIT THEN
    DUP SYM-REC REC-NAME C@ CALLLEN @ = IF
      DUP SYM-REC REC-NAME 1+ CALLBUF CALLLEN @ STR= IF
        SWAP DROP EXIT
      THEN
    THEN
    1+ SWAP 1- SWAP
  AGAIN
;

: SYM-ADD ( type aux -- off )
  SYMCOUNT @ 64 >= IF FAIL THEN

  \ bytes (keep type+aux for record)
  OVER 2 = IF
    DUP 2 LSHIFT ALIGN8
  ELSE
    8
  THEN
  LOCOFF @ + DUP LOCOFF ! \ type aux off

  \ store record
  SYMCOUNT @ SYM-REC >R

  \ aux at +16
  SWAP \ type off aux
  DUP R@ 16 + !
  DROP \ type off

  \ type at +8
  SWAP \ off type
  DUP R@ 8 + !

  \ off at +0
  OVER R@ !
  DROP

  \ name at +24
  CALLLEN @ R@ REC-NAME C!
  CALLBUF R@ REC-NAME 1+ CALLLEN @ CMOVE

  R> DROP
  SYMCOUNT @ 1+ SYMCOUNT !
;

\ =========================================================
\ Codegen helpers (text emission)
\ =========================================================

: .COMMA  ( -- ) 44 EMIT ;
: .HASH   ( -- ) 35 EMIT ;
: .LBRAK  ( -- ) 91 EMIT ;
: .RBRAK  ( -- ) 93 EMIT ;
: .EXCL   ( -- ) 33 EMIT ;
: .COLON  ( -- ) 58 EMIT ;
: .DOT    ( -- ) 46 EMIT ;
: .MINUS  ( -- ) 45 EMIT ;
: .0X     ( -- ) 48 EMIT 120 EMIT ;

: IND ( -- ) SPACE SPACE ;

: MASK32 ( -- m ) 1 32 LSHIFT 1- ;

: >HEXCHAR ( n -- c ) DUP 10 < IF 48 + ELSE 87 + THEN ;
: EMITHEX ( n -- ) >HEXCHAR EMIT ;

: .HEX32 ( n -- )
  MASK32 AND
  DUP 28 RSHIFT 15 AND EMITHEX
  DUP 24 RSHIFT 15 AND EMITHEX
  DUP 20 RSHIFT 15 AND EMITHEX
  DUP 16 RSHIFT 15 AND EMITHEX
  DUP 12 RSHIFT 15 AND EMITHEX
  DUP 8  RSHIFT 15 AND EMITHEX
  DUP 4  RSHIFT 15 AND EMITHEX
  DUP 0  RSHIFT 15 AND EMITHEX
  DROP
;

: .IMM ( n -- ) .HASH .0X .HEX32 ;
: .NEGIMM ( n -- ) .HASH .MINUS .0X .HEX32 ;

: .W ( n -- ) 119 EMIT 48 + EMIT ; \ w0..w9
: .X ( n -- ) 120 EMIT 48 + EMIT ; \ x0..x9
: .X29 ( -- ) 120 EMIT 50 EMIT 57 EMIT ;
: .X30 ( -- ) 120 EMIT 51 EMIT 48 EMIT ;
: .SP  ( -- ) 115 EMIT 112 EMIT ;

: .GLOBAL ( -- ) .DOT 103 EMIT 108 EMIT 111 EMIT 98 EMIT 97 EMIT 108 EMIT ;
: .ALIGN  ( -- ) .DOT 97 EMIT 108 EMIT 105 EMIT 103 EMIT 110 EMIT ;

: .STP  ( -- ) 115 EMIT 116 EMIT 112 EMIT ;
: .LDP  ( -- ) 108 EMIT 100 EMIT 112 EMIT ;
: .MOV  ( -- ) 109 EMIT 111 EMIT 118 EMIT ;
: .SUB  ( -- ) 115 EMIT 117 EMIT 98 EMIT ;
: .ADD  ( -- ) 97 EMIT 100 EMIT 100 EMIT ;
: .MUL  ( -- ) 109 EMIT 117 EMIT 108 EMIT ;
: .SDIV ( -- ) 115 EMIT 100 EMIT 105 EMIT 118 EMIT ;
: .MSUB ( -- ) 109 EMIT 115 EMIT 117 EMIT 98 EMIT ;
: .CMP  ( -- ) 99 EMIT 109 EMIT 112 EMIT ;
: .CSET ( -- ) 99 EMIT 115 EMIT 101 EMIT 116 EMIT ;
: .CBZ  ( -- ) 99 EMIT 98 EMIT 122 EMIT ;
: .B    ( -- ) 98 EMIT ;
: .BL   ( -- ) 98 EMIT 108 EMIT ;
: .LDR  ( -- ) 108 EMIT 100 EMIT 114 EMIT ;
: .STR  ( -- ) 115 EMIT 116 EMIT 114 EMIT ;
: .LSL  ( -- ) 108 EMIT 115 EMIT 108 EMIT ;
: .SXTW ( -- ) 115 EMIT 120 EMIT 116 EMIT 119 EMIT ;
: .NEG  ( -- ) 110 EMIT 101 EMIT 103 EMIT ;
: .RET  ( -- ) 114 EMIT 101 EMIT 116 EMIT ;

: .EQ ( -- ) 101 EMIT 113 EMIT ;
: .NE ( -- ) 110 EMIT 101 EMIT ;
: .LT ( -- ) 108 EMIT 116 EMIT ;
: .LE ( -- ) 108 EMIT 101 EMIT ;
: .GT ( -- ) 103 EMIT 116 EMIT ;
: .GE ( -- ) 103 EMIT 101 EMIT ;

: EMIT-FN ( -- ) 95 EMIT FNBUF FNLEN @ TYPE ;
: EMIT-CALL ( -- ) 95 EMIT CALLEEBUF CALLEELEN @ TYPE ;

: .LBL ( id -- ) .DOT 76 EMIT .HEX32 ;
: .LBLDEF ( id -- ) .LBL .COLON CR ;

: GEN-HEADER ( -- )
  .GLOBAL SPACE EMIT-FN CR
  .ALIGN SPACE 52 EMIT CR \ ".align 4"
  EMIT-FN .COLON CR
;

: GEN-PROLOGUE ( -- )
  IND .STP SPACE .X29 .COMMA SPACE .X30 .COMMA SPACE
  .LBRAK .SP .COMMA SPACE .HASH .MINUS 49 EMIT 54 EMIT .RBRAK .EXCL CR \ #-16
  IND .MOV SPACE .X29 .COMMA SPACE .SP CR
  IND .SUB SPACE .SP .COMMA SPACE .SP .COMMA SPACE 512 .IMM CR \ fixed frame 0x200
;

: GEN-EPILOGUE ( -- )
  IND .MOV SPACE .SP .COMMA SPACE .X29 CR
  IND .LDP SPACE .X29 .COMMA SPACE .X30 .COMMA SPACE
  .LBRAK .SP .RBRAK .COMMA SPACE .HASH 49 EMIT 54 EMIT CR \ #16
  IND .RET CR
;

: GEN-MOV-W0-IMM ( n -- )
  IND .MOV SPACE 0 .W .COMMA SPACE .IMM CR
;

: GEN-ADDR-X29 ( off -- )
  IND .SUB SPACE 0 .X .COMMA SPACE .X29 .COMMA SPACE .IMM CR
;

: GEN-LDR-W0-X0 ( -- )
  IND .LDR SPACE 0 .W .COMMA SPACE .LBRAK 0 .X .RBRAK CR
;

: GEN-LDR-X0-X0 ( -- )
  IND .LDR SPACE 0 .X .COMMA SPACE .LBRAK 0 .X .RBRAK CR
;

: GEN-STR-W0-X1 ( -- )
  IND .STR SPACE 0 .W .COMMA SPACE .LBRAK 1 .X .RBRAK CR
;

: GEN-STR-X0-X1 ( -- )
  IND .STR SPACE 0 .X .COMMA SPACE .LBRAK 1 .X .RBRAK CR
;

: GEN-STRW-X29 ( reg off -- )
  IND .STR SPACE SWAP .W .COMMA SPACE
  .LBRAK .X29 .COMMA SPACE .NEGIMM .RBRAK CR
;

: GEN-PUSH-W0 ( -- )
  IND .STR SPACE 0 .W .COMMA SPACE
  .LBRAK .SP .COMMA SPACE .HASH .MINUS 49 EMIT 54 EMIT .RBRAK .EXCL CR
;

: GEN-POP-W1 ( -- )
  IND .LDR SPACE 1 .W .COMMA SPACE
  .LBRAK .SP .RBRAK .COMMA SPACE .HASH 49 EMIT 54 EMIT CR
;

: GEN-PUSH-X0 ( -- )
  IND .STR SPACE 0 .X .COMMA SPACE
  .LBRAK .SP .COMMA SPACE .HASH .MINUS 49 EMIT 54 EMIT .RBRAK .EXCL CR
;

: GEN-POP-X1 ( -- )
  IND .LDR SPACE 1 .X .COMMA SPACE
  .LBRAK .SP .RBRAK .COMMA SPACE .HASH 49 EMIT 54 EMIT CR
;

: GEN-POP-ARG ( n -- )
  IND .LDR SPACE .W .COMMA SPACE
  .LBRAK .SP .RBRAK .COMMA SPACE .HASH 49 EMIT 54 EMIT CR
;

: GEN-B ( id -- ) IND .B SPACE .LBL CR ;
: GEN-CBZ ( id -- ) IND .CBZ SPACE 0 .W .COMMA SPACE .LBL CR ;
: GEN-CALL ( -- ) IND .BL SPACE EMIT-CALL CR ;

\ =========================================================
\ Expression codegen & types
\ =========================================================

\ Expr types:
\   0 = int rvalue (w0)
\   1 = ptr rvalue (x0)
\   2 = int lvalue (x0 = address)
\   3 = ptr lvalue (x0 = address)

: BASE ( ty -- base ) 1 AND ;
: LV?  ( ty -- f ) 2 AND ;

: RVAL ( ty -- ty' )
  DUP LV? IF
    DUP BASE IF
      GEN-LDR-X0-X0
      DROP 1 EXIT
    THEN
    GEN-LDR-W0-X0
    DROP 0 EXIT
  THEN
;

: WANT-INT ( ty -- ) RVAL DUP 0 = 0= IF FAIL THEN DROP ;
: WANT-PTR ( ty -- ) RVAL DUP 1 = 0= IF FAIL THEN DROP ;

: TY-INT-LV ( -- ty ) 2 ;
: TY-PTR-LV ( -- ty ) 3 ;

: CALL-EXPR ( -- ty ) EXPRXT @ EXECUTE ;
: CALL-STMT ( -- ) STMTXT @ EXECUTE ;

\ =========================================================
\ Expression parser (recursive descent)
\ =========================================================

: PRIMARY ( -- ty )
  TOK @ 40 = IF \ '('
    40 EXPECT
    CALL-EXPR
    41 EXPECT
    EXIT
  THEN

  TOK @ TK_NUM = IF
    TOKVAL @ GEN-MOV-W0-IMM
    NEXTTOK
    0 EXIT
  THEN

  TOK @ TK_ID = IF
    SAVE-ID
    NEXTTOK

    \ call?
    TOK @ 40 = IF
      SAVE-CALLEE
      40 EXPECT
      0 \ argc
      TOK @ 41 = IF
        41 EXPECT
      ELSE
        BEGIN
          CALL-EXPR WANT-INT
          GEN-PUSH-W0
          1+
          TOK @ 44 = IF
            44 EXPECT
            0
          ELSE
            -1
          THEN
        UNTIL
        41 EXPECT
      THEN
      DUP 8 > IF FAIL THEN
      BEGIN
        DUP 0= IF
          DROP -1
        ELSE
          1- DUP GEN-POP-ARG
          0
        THEN
      UNTIL
      GEN-CALL
      0 EXIT
    THEN

    \ variable (CALLBUF/CALLLEN)
    SYM-FIND DUP -1 = IF FAIL THEN
    SYM-REC >R
    R@ @        \ off
    R@ 8 + @    \ type
    R> DROP     \ off type
    DUP 2 = IF \ array => ptr rvalue
      DROP
      GEN-ADDR-X29
      1 EXIT
    THEN
    OVER GEN-ADDR-X29
    SWAP DROP
    0= IF TY-INT-LV ELSE TY-PTR-LV THEN
    EXIT
  THEN

  FAIL
;

: POSTFIX ( -- ty )
  PRIMARY
  BEGIN
    TOK @ 91 = IF \ '['
      WANT-PTR
      GEN-PUSH-X0
      91 EXPECT
      CALL-EXPR WANT-INT
      93 EXPECT
      GEN-POP-X1
      \ scale index and add: w0 <<=2; sxtw x0,w0; add x0,x1,x0
      IND .LSL SPACE 0 .W .COMMA SPACE 0 .W .COMMA SPACE .HASH 50 EMIT CR \ #2
      IND .SXTW SPACE 0 .X .COMMA SPACE 0 .W CR
      IND .ADD SPACE 0 .X .COMMA SPACE 1 .X .COMMA SPACE 0 .X CR
      TY-INT-LV
    ELSE
      EXIT
    THEN
  AGAIN
;

: UNARY ( -- ty )
  TOK @ 45 = IF \ '-'
    45 EXPECT
    UNARY WANT-INT
    IND .NEG SPACE 0 .W .COMMA SPACE 0 .W CR
    0 EXIT
  THEN
  TOK @ 38 = IF \ '&'
    38 EXPECT
    UNARY DUP LV? 0= IF FAIL THEN DROP
    1 EXIT
  THEN
  TOK @ 42 = IF \ '*'
    42 EXPECT
    UNARY WANT-PTR
    TY-INT-LV EXIT
  THEN
  POSTFIX
;

: MUL ( -- ty )
  UNARY
  BEGIN
    TOK @ 42 = IF \ '*'
      WANT-INT GEN-PUSH-W0
      42 EXPECT
      UNARY WANT-INT
      GEN-POP-W1
      IND .MUL SPACE 0 .W .COMMA SPACE 1 .W .COMMA SPACE 0 .W CR
      0
    ELSE TOK @ 47 = IF \ '/'
      WANT-INT GEN-PUSH-W0
      47 EXPECT
      UNARY WANT-INT
      GEN-POP-W1
      IND .SDIV SPACE 0 .W .COMMA SPACE 1 .W .COMMA SPACE 0 .W CR
      0
    ELSE TOK @ 37 = IF \ '%'
      WANT-INT GEN-PUSH-W0
      37 EXPECT
      UNARY WANT-INT
      GEN-POP-W1
      IND .SDIV SPACE 2 .W .COMMA SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .MSUB SPACE 0 .W .COMMA SPACE 2 .W .COMMA SPACE 0 .W .COMMA SPACE 1 .W CR
      0
    ELSE
      EXIT
    THEN THEN THEN
  AGAIN
;

: ADD ( -- ty )
  MUL
  BEGIN
    TOK @ 43 = IF \ '+'
      WANT-INT GEN-PUSH-W0
      43 EXPECT
      MUL WANT-INT
      GEN-POP-W1
      IND .ADD SPACE 0 .W .COMMA SPACE 1 .W .COMMA SPACE 0 .W CR
      0
    ELSE TOK @ 45 = IF \ '-'
      WANT-INT GEN-PUSH-W0
      45 EXPECT
      MUL WANT-INT
      GEN-POP-W1
      IND .SUB SPACE 0 .W .COMMA SPACE 1 .W .COMMA SPACE 0 .W CR
      0
    ELSE
      EXIT
    THEN THEN
  AGAIN
;

: REL ( -- ty )
  ADD
  BEGIN
    TOK @ 60 = IF \ '<'
      WANT-INT GEN-PUSH-W0
      60 EXPECT
      ADD WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .LT CR
      0
    ELSE TOK @ TK_LE = IF
      WANT-INT GEN-PUSH-W0
      TK_LE EXPECT
      ADD WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .LE CR
      0
    ELSE TOK @ 62 = IF \ '>'
      WANT-INT GEN-PUSH-W0
      62 EXPECT
      ADD WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .GT CR
      0
    ELSE TOK @ TK_GE = IF
      WANT-INT GEN-PUSH-W0
      TK_GE EXPECT
      ADD WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .GE CR
      0
    ELSE
      EXIT
    THEN THEN THEN THEN
  AGAIN
;

: EQ ( -- ty )
  REL
  BEGIN
    TOK @ TK_EQEQ = IF
      WANT-INT GEN-PUSH-W0
      TK_EQEQ EXPECT
      REL WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .EQ CR
      0
    ELSE TOK @ TK_NEQ = IF
      WANT-INT GEN-PUSH-W0
      TK_NEQ EXPECT
      REL WANT-INT
      GEN-POP-W1
      IND .CMP SPACE 1 .W .COMMA SPACE 0 .W CR
      IND .CSET SPACE 0 .W .COMMA SPACE .NE CR
      0
    ELSE
      EXIT
    THEN THEN
  AGAIN
;

: ASSIGN ( -- ty )
  EQ
  TOK @ 61 = IF
    DUP LV? 0= IF FAIL THEN
    BASE >R
    GEN-PUSH-X0
    61 EXPECT
    ASSIGN
    R@ IF WANT-PTR ELSE WANT-INT THEN
    GEN-POP-X1
    R@ IF GEN-STR-X0-X1 ELSE GEN-STR-W0-X1 THEN
    R>
  THEN
;

: EXPR ( -- ty ) ASSIGN ;

\ Hook EXPR for parentheses/calls (xt stored in CCBASE cell)
' EXPR EXPRXT !

\ =========================================================
\ Statements
\ =========================================================

: NEWLBL ( -- id ) LBLCOUNT @ DUP 1+ LBLCOUNT ! ;
: GEN-RETJMP ( -- ) RETLBL @ GEN-B ;

\ Saved token record lives in SAVTOKPTR @ (56 bytes)
: TOK-SAVE ( -- )
  SAVTOKPTR @ >R
  TOK @ R@ !
  TOKVAL @ R@ REC-VAL !
  TOKLEN @ R@ REC-LEN !
  IDBUF R@ REC-NAME 32 CMOVE
  R> DROP
;

: TOK-RESTORE ( -- )
  SAVTOKPTR @ >R
  R@ @ TOK !
  R@ REC-VAL @ TOKVAL !
  R@ REC-LEN @ TOKLEN !
  R@ REC-NAME IDBUF 32 CMOVE
  R> DROP
;

: TBUF-RESET ( -- ) 0 TBUFN ! 0 TBIDX ! ;

: TBUF-APPEND ( -- )
  TBUFN @ 40 >= IF FAIL THEN
  TBUFN @ TBUF-REC >R
  TOK @ R@ !
  TOKVAL @ R@ REC-VAL !
  TOKLEN @ R@ REC-LEN !
  IDBUF R@ REC-NAME 32 CMOVE
  R> DROP
  TBUFN @ 1+ TBUFN !
;

: REPLAY-EXPR ( -- )
  TOK-SAVE
  1 SRCMODE !
  0 TBIDX !
  NEXTTOK
  TOK @ 0<> IF CALL-EXPR RVAL DROP THEN
  0 SRCMODE !
  TOK-RESTORE
;

: BLOCK ( -- )
  123 EXPECT
  BEGIN
    TOK @ 125 = IF 125 EXPECT EXIT THEN
    CALL-STMT
  AGAIN
;

: DECL ( -- )
  KW_INT EXPECT
  0 \ type=int
  TOK @ 42 = IF 42 EXPECT DROP 1 THEN \ type=ptr
  EXPECT-ID
  TOK @ 91 = IF
    91 EXPECT
    EXPECT-NUM
    93 EXPECT
    SWAP DROP \ drop ptr/int type
    2 SWAP \ type=array, aux=n
  ELSE
    0 \ aux=0
  THEN
  SYM-ADD DROP
  59 EXPECT
;

: RETURN-STMT ( -- )
  KW_RETURN EXPECT
  CALL-EXPR WANT-INT
  59 EXPECT
  GEN-RETJMP
;

: IF-STMT ( -- )
  KW_IF EXPECT
  40 EXPECT
  CALL-EXPR WANT-INT
  41 EXPECT
  NEWLBL NEWLBL \ else end
  OVER GEN-CBZ
  CALL-STMT
  TOK @ KW_ELSE = IF
    DUP GEN-B
    SWAP .LBLDEF
    KW_ELSE EXPECT
    CALL-STMT
    .LBLDEF
  ELSE
    DROP
    .LBLDEF
  THEN
;

: WHILE-STMT ( -- )
  KW_WHILE EXPECT
  NEWLBL NEWLBL \ start end
  OVER .LBLDEF
  40 EXPECT
  CALL-EXPR WANT-INT
  41 EXPECT
  DUP GEN-CBZ
  CALL-STMT
  OVER GEN-B
  SWAP DROP .LBLDEF
;

: FOR-STMT ( -- )
  KW_FOR EXPECT
  40 EXPECT

  \ init
  TOK @ 59 = IF
    59 EXPECT
  ELSE
    CALL-EXPR RVAL DROP
    59 EXPECT
  THEN

  NEWLBL NEWLBL \ cond end
  OVER .LBLDEF

  \ cond (empty => true)
  TOK @ 59 = IF
    1 GEN-MOV-W0-IMM
    59 EXPECT
  ELSE
    CALL-EXPR WANT-INT
    59 EXPECT
  THEN
  DUP GEN-CBZ

  \ buffer inc tokens until ')'
  TBUF-RESET
  BEGIN
    TOK @ 41 = IF
      -1
    ELSE
      TBUF-APPEND
      NEXTTOK
      0
    THEN
  UNTIL
  41 EXPECT

  \ body
  CALL-STMT

  \ inc
  TBUFN @ 0<> IF REPLAY-EXPR THEN

  OVER GEN-B
  SWAP DROP .LBLDEF
;

: EXPR-STMT ( -- )
  CALL-EXPR RVAL DROP
  59 EXPECT
;

: STMT ( -- )
  TOK @ 123 = IF BLOCK EXIT THEN
  TOK @ KW_RETURN = IF RETURN-STMT EXIT THEN
  TOK @ KW_IF = IF IF-STMT EXIT THEN
  TOK @ KW_WHILE = IF WHILE-STMT EXIT THEN
  TOK @ KW_FOR = IF FOR-STMT EXIT THEN
  TOK @ KW_INT = IF DECL EXIT THEN
  TOK @ 59 = IF 59 EXPECT EXIT THEN
  EXPR-STMT
;

\ Hook STMT for nested statement compilation
' STMT STMTXT !

\ =========================================================
\ Functions / translation unit
\ =========================================================

: PARAMS ( -- )
  40 EXPECT
  TOK @ 41 = IF 41 EXPECT EXIT THEN
  0 \ arg index
  BEGIN
    KW_INT EXPECT
    EXPECT-ID
    0 0 SYM-ADD \ type=int aux=0 -> off
    OVER >R
    GEN-STRW-X29
    R> 1+
    TOK @ 44 = IF
      44 EXPECT
      0
    ELSE
      -1
    THEN
  UNTIL
  41 EXPECT
  DROP
;

: FUNC ( -- )
  SYM-INIT
  KW_INT EXPECT

  \ function name into FNBUF/FNLEN
  TOK @ TK_ID = 0= IF FAIL THEN
  TOKLEN @ DUP FNLEN ! >R
  IDBUF FNBUF R> CMOVE
  NEXTTOK

  NEWLBL RETLBL !
  GEN-HEADER
  GEN-PROLOGUE
  PARAMS
  BLOCK

  \ default fallthrough: return 0
  0 GEN-MOV-W0-IMM
  GEN-RETJMP
  RETLBL @ .LBLDEF
  GEN-EPILOGUE
;

: CC-ALLOC ( -- )
  \ Allocate buffers/tables once (during CC run).
  \ With the Stage 1 param stack moved to the top of the 64KB buffer,
  \ the dictionary has room to grow and can safely hold these scratch areas.
  HERE 64 ALLOT FNPTR !
  HERE 64 ALLOT CALLPTR !
  HERE 64 ALLOT CALLEEPTR !
  HERE 128 ALLOT IDPTR !
  HERE 56 ALLOT SAVTOKPTR !
  HERE 2240 ALLOT TBUFPTR !
  HERE 3584 ALLOT SYMTABPTR !
;

: CC ( -- )
  0 UNGET-COUNT !
  0 LBLCOUNT !
  0 SRCMODE !
  CC-ALLOC
  NEXTTOK
  BEGIN
    TOK @ 0= IF BYE THEN
    FUNC
  AGAIN
;

CC
