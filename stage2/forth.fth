\ Stage 2: Extended Forth
\ Implements higher-level words on top of Stage 1 primitives.

\ =========================================================
\ Compilation Helpers (needed first for IF/THEN/ELSE)
\ =========================================================

: [COMPILE] ' , ; IMMEDIATE

\ Compile the execution token (xt) of the next word as a literal.
\ This relies on Stage 1 providing an IMMEDIATE LITERAL word.
: ['] ' [COMPILE] LITERAL ; IMMEDIATE

\ =========================================================
\ Control Flow (needed before ?DUP)
\ =========================================================

: IF ( -- addr )
  ['] 0BRANCH ,   \ Compile 0BRANCH
  HERE            \ Save location of the offset
  0 ,             \ Placeholder for the offset
; IMMEDIATE

: THEN ( addr -- )
  HERE OVER -     \ Calculate offset
  SWAP !          \ Patch the offset at the saved location
; IMMEDIATE

: ELSE ( addr -- addr' )
  ['] BRANCH ,    \ Compile BRANCH
  HERE            \ Save location for new offset
  0 ,             \ Placeholder
  SWAP [COMPILE] THEN \ Patch the IF branch to point here
; IMMEDIATE

: BEGIN ( -- addr )
  HERE
; IMMEDIATE

: UNTIL ( addr -- )
  ['] 0BRANCH ,
  HERE - ,        \ Compile back-offset
; IMMEDIATE

: AGAIN ( addr -- )
  ['] BRANCH ,
  HERE - ,        \ Compile back-offset
; IMMEDIATE

\ =========================================================
\ Basic Stack & Logic
\ =========================================================

: NIP ( a b -- b ) SWAP DROP ;
: TUCK ( a b -- b a b ) SWAP OVER ;
: ?DUP ( n -- n n | 0 ) DUP IF DUP THEN ;
: ROT ( a b c -- b c a ) >R SWAP R> SWAP ;
: 2DROP ( a b -- ) DROP DROP ;
: 2DUP ( a b -- a b a b ) OVER OVER ;

\ =========================================================
\ Strings
\ =========================================================

: SPACE 32 EMIT ;
: CR 10 EMIT ;

\ =========================================================
\ Test (commented out for production)
\ =========================================================

\ : GREET
\   72 EMIT 101 EMIT 108 EMIT 108 EMIT 111 EMIT CR
\ ;
\ GREET
