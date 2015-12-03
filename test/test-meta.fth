: noop ;

create data_stack   110 cells allot
create return_stack   256 cells allot
create jmpbuf         jmp_buf allot

variable dictionary_end

: cell    cell ; \ Metacompiler knows what to do.
: cell+   cell + ;

: 3drop   2drop drop ;
: rot    >r swap r> swap ;
: 2r>   r> r> r> rot >r swap ;
: 3dup   >r >r r@ over 2r> over >r rot swap r> ;
: unloop    r> 2r> 2drop >r ;
forward: <
: min   2dup < if drop else nip then ;
: bounds   over + swap ;
: count    dup 1+ swap c@ ;
: i    r> r@ swap >r ;
: cr   10 emit ;
: type   bounds do i c@ emit loop ;
: perform   @ execute ;
variable state
: <   2dup xor 0< if drop 0< else - 0< then ;
: cmove ( addr1 addr2 n -- )   ?dup if bounds do count i c! loop drop
   else 2drop then ;
: cabs   127 over < if 256 swap - then ;
0 value latestxt

include dictionary.fth

: lowercase? ( c -- flag )   dup [char] a < if drop 0 exit then [ char z 1+ ] literal < ;
: upcase ( c1 -- c2 )   dup lowercase? if [ char A char a - ] literal + then ;
: c<> ( c1 c2 -- flag )   upcase swap upcase <> ;

: name= ( ca1 u1 ca2 u2 -- flag )
   2>r r@ <> 2r> rot if 3drop 0 exit then
   bounds do
      dup c@ i c@ c<> if drop unloop 0 exit then
      1+
  loop drop -1 ;
: nt= ( ca u nt -- flag )   >name name= ;

: immediate?   c@ 127 swap < if 1 else -1 then ;

: traverse-wordlist ( wid xt -- ) ( xt: nt -- continue? )
   >r >body @ begin dup while
      r@ over >r execute r> swap
      while >nextxt
   repeat then r> 2drop ;

: ?nt>xt ( -1 ca u nt -- 0 xt i? 0 | -1 ca u -1 )
   3dup nt= if >r 3drop 0 r> dup immediate? 0
   else drop -1 then ;
: (find) ( ca u wl -- ca u 0 | xt 1 | xt -1 )
   2>r -1 swap 2r> ['] ?nt>xt traverse-wordlist rot if 0 then ;
: search-wordlist ( ca u wl -- 0 | xt 1 | xt -1 )
   (find) ?dup 0= if 2drop 0 then ;

defer abort
: undef ( a u -- )   ." Undefined: " type cr abort ;
: ?undef ( a u x -- a u )   if undef then ;

: literal   compile (literal) , ; immediate
: ?literal ( x -- )   state @ if [compile] literal then ;

defer number

: (number) ( a u -- )
   over c@ [char] - = dup >r if swap 1+ swap 1 - then
   0 rot rot
   begin dup while
      over c@ [char] 0 - -1 over < while dup 10 < while
      2>r 1+ swap dup dup + dup + + dup +  r> + swap r> 1 -
   repeat then drop then
   ?dup ?undef drop r> if negate then  ?literal ;

variable >in
variable input
: input@ ( u -- a )   cells input @ + ;
: 'source   0 input@ ;
: #source   1 input@ ;
: source#   2 input@ ;
: 'refill   3 input@ ;
: 'prompt   4 input@ ;
: source>   5 input@ ;
6 cells constant /input-source

create forth  2 cells allot
create compiler-words  2 cells allot
create included-files  2 cells allot
create context  9 cells allot

: r@+   r> r> dup cell+ >r @ swap >r ;
: search-context ( a u context -- a 0 | xt ? )   >r begin r@+ ?dup while
   (find) ?dup until else drop 0 then r> drop ;
: find-name ( a u -- a u 0 | xt ? )   swap over #name min context
   search-context ?dup if rot drop else swap 0 then ;

: source   'source @  #source @ ;
: source? ( -- flag )   >in @ source nip < ;
: <source ( -- char|-1 )   source >in @ dup rot = if
   2drop -1 else + c@  1 >in +! then ;

32 constant bl
: blank?   dup bl =  over 8 = or  over 9 = or  over 10 = or  swap 13 = or ;
: skip ( "<blanks>" -- )   begin source? while
   <source blank? 0= until -1 >in +! then ;
: parse-name ( "<blanks>name<blank>" -- a u )   skip  source drop >in @ +
   0 begin source? while 1+ <source blank? until 1 - then ;

: (previous)   ['] forth context ! ;

defer also
defer previous
defer catch

create interpreters  ' execute , ' number , ' execute ,
: ?exception   if cr ." Exception!" cr then ;
: interpret-xt   1+ cells  interpreters + @ catch ?exception ;

: [   0 state !  ['] execute interpreters !  previous ; immediate
: ]   1 state !  ['] compile, interpreters !
   also ['] compiler-words context ! ;

variable csp

: .latest   latestxt >name type ;
: ?bad   rot if type ."  definition: " .latest cr abort then 2drop ;
: !csp   csp @ s" Nested" ?bad  sp@ csp ! ;
: ?csp   sp@ csp @ <> s" Unbalanced" ?bad  0 csp ! ;

: (does>)   r> does! ;

\ If you change the definition of :, you also need to update the
\ offset to the runtime code in the metacompiler(s).
: :   parse-name header, 'dodoes , ] !csp  does> >r ;
: ;   reveal compile exit [compile] [ ?csp ; immediate

: refill   0 >in !  0 #source !  'refill perform ;
: ?prompt    'prompt perform ;
: source-id   source# @ ;

256 constant /file

: file-refill   'source @ /file bounds do
      i 1 source-id read-file if 0 unloop exit then
      0= if source nip unloop exit then
      i c@ 10 = if leave then
      1 #source +!
   loop -1 ;

0 value file-source

: save-input   >in @ input @ 2 ;
: restore-input   drop input ! >in ! 0 ;

defer backtrace

: sigint   cr backtrace abort ;

\ ----------------------------------------------------------------------

( File Access words. )

: n>r   r> over >r swap begin ?dup while rot r> 2>r 1 - repeat >r ;
: nr>   r> r@ begin ?dup while 2r> >r rot rot 1 - repeat r> swap >r ;

0 constant sp0
0 constant rp0
0 constant dp0

defer parsed
: (parsed) ( a u -- )   find-name interpret-xt ;
: ?stack   sp0 sp@ cell+ < abort" Stack underflow" ;
: interpret   begin parse-name dup while parsed ?stack repeat 2drop ;
: interpreting   begin refill while interpret ?prompt repeat ;

: 0source   'prompt !  'refill !  source# !  'source !  0 source> ! ;
: source, ( 'source sourceid refill prompt -- )
   input @ >r  here input !  /input-source allot  0source  r> input ! ;

create tib   256 allot
: key   here dup 1 0 read-file abort" Read error"  0= if bye then  c@ ;
: terminal-refill   tib 256 bounds do
      key dup 10 = if drop leave then
      i c!  1 #source +!
   loop -1 ;
: ok   state @ 0= if ."  ok" cr then ;
create terminal-source   6 cells allot
: terminal-input   terminal-source input !
   tib 0 ['] terminal-refill ['] ok 0source ;
   
: quit   0 csp !  [compile] [  terminal-input interpreting ;

host also meta
\ cr .( Target size: ) t-size .
\ cr .( Target used: ) target here host also meta >host t-image host - .
\ cr .( Host unused: ) unused .
target



' noop is also
' (previous) is previous
' (parsed) is parsed
' (number) is number
: dummy-catch   execute 0 ;
' dummy-catch is catch

: string-refill   0 ;

create string-source  6 cells allot

: string-source-init   string-source input !
   0 -1 ['] string-refill ['] noop 0source ;

: string-input ( a u -- )   string-source input !  0 >in !
   #source !  'source ! ;

[undefined] 2dup [if]
.( We should not get here. )
: 2dup   over over ;
[then]

: (abort)   ." ABORT!" bye ;
' (abort) is abort

variable x
: foo   70 x !  x @ emit  1 x +!  x @ emit ;

0 value fd
create buf 22 allot

: readme   s" README.md" 0 open-file abort" Error opening file" to fd
           buf 22 fd read-file abort" Error reading file"
           buf 22 type
           fd close-file abort" Error closing file" ;

defer baz
' foo is baz

16 constant sixteen

' noop >code @ constant 'docol

: it-works  ." It works!" cr ;
: colon   : compile it-works [compile] ; ;
: test-colon   s" blah" string-input  colon  latestxt execute ;

: space   ."  " ;

variable counter  char A ' counter >body !
: exclam   ." We're here: " counter @ emit 1 counter +! ." !" cr ;

' forth ' context >body !
' forth ' context >body 4 + !
0 ' context >body 8 + !
' forth ' current >body !
0 ' compiler-words >body !
' forth ' compiler-words >body cell+ !

: face   if ." :) " else ." :( " then ;

: .word   >name type space ;
: (words)   begin ?dup while dup .word >nextxt repeat ;
: words   current @ >body @ (words) ;

' words ' forth >body !

forward: bar
: hello   s" hello " type ;
: test=  2dup type space s" foo" name= face ;
: warm   ." lbForth" cr
         dp0 dp !
         s" bye" s" 2r>" name= face
         s" bye" s" 2r>" name= face cr
         s" 0" find-name face drop
         s" bye" find-name face drop
         s" FOO" find-name face execute
	 s" Readme" ['] forth (find) face execute
	 s" EXCLAM" ['] forth search-wordlist face execute
	 test-colon
	 words cr
	 s" Blah" find-name face execute
         foo baz bar cr readme ['] hello execute quit bye ;
: bar   sixteen cells 1+ 2 or 1 xor emit ;

code cold
   then,

   ' warm >body # I mov,
   ' data_stack >body 100 cells + # S mov,
   ' return_stack >body 256 cells + # R mov,

   S ' sp0 >body mov,
   R ' rp0 >body mov,

   next,
end-code

here ' dp0 >body !
10000 elf-extra-bytes!
