* Program.: CREATE.CMD
* Author..: Luis A. Castro. 
* Date....: 02/02/83. 
* Notice..: Copyright 1983,  ASHTON-TATE.
* Notes...: Creates a command file header and footer
*    documentation. This is the recommend way to
*    document command files.

SET TALK OFF 
SET INTENSITY OFF 

* Replace my name with your name and
* replace our copyright notice with your's. 
STORE "Luis A. Castro" TO yourname
STORE "Copyright 1983,  ASHTON-TATE" TO notice

ERASE
?
? '* Program...:'
? '* Author(s).:'+yourname
? '* Date......:'
? '* Notice....:'+notice
? '* Called by.:'
? '* Call(s)...:' 
? '* Notes.....:'
@ 0,0

* Get program file name...
ACCEPT '* Program...' to filename
IF @('.',filename) > 0
   STORE $(filename,1,@('.',filename)-1) to filename
ENDIF
IF filename=' '
   ERASE
   RETURN
ENDIF
STORE !(filename)+'.CMD' TO filename
IF FILE(filename)
   @ 10,0
   ? '*** FILE ALREADY EXISTS ***'
   CLEAR
   RETURN
ENDIF

* Next, get the rest of the information...
?
ACCEPT '* Date......' TO date
?
ACCEPT '* Called by.' TO called:by
ACCEPT '* Call(s)...' TO calls
ACCEPT '* Notes.....' TO notes

* Now, create the command file...
ERASE
SET ALTERNATE TO &filename
SET ALTERNATE ON
? '* Program...: '+filename
? '* Author(s).: '+yourname
? '* Date......: '+date
? '* Notice....: '+notice
? '* Called by.: '+called:by
? '* Call(s)...: '+calls
? '* Notes.....: '+notes
?
? '* Set flags go here...'
? 'SET TALK OFF'
?
? '* Store statements follow...'
? "STORE ' ' TO select"
?
? '* <body of program goes here>'
?
? '* <release local memory variables>'
? 'RELEASE select'
? 'RETURN'
? '* EOF '+filename
? '* <list of parameters passed>'
SET ALTERNATE OFF

CLEAR
RETURN
* EOF create.cmd 
