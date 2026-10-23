* 01/27/83   for Ashton-Tate    by joe stegman
*   Demonstration program   EMPLOYEE REPORT,   EMP-RPRT.cmd
*         dBASE II(tm)    release 2.4
*
*  the user should be able to list employees by name or number
*    to either the console or the printer...
*
*  also should be able to list all employees in a certain group
*  i.e. all those in dept ABC, or those in the same zip:code...
*       You will be able to add these features without much difficulty
*
*   Local variables start with >Mer<
*
CLEAR
SET talk OFF
USE EMPLOYEE

DO WHILE T

  ERASE
  TEXT

  Then employee report may be printed by employee name or by employee number.

         Enter "1" to list by employee name,
          or   "2" to list by employee number,
          or   RETURN  to display main menu.

  ENDTEXT

  STORE "." TO Mer:type
  DO WHILE .not. Mer:type$'12 '
    *   assume we want to display the main menu again...
    STORE ' ' TO Mer:type
    SET colon OFF
    @ 11,5 SAY '     Enter the listing selection ? ' GET Mer:type PICTURE '9'
    SET colon ON
    READ
  ENDDO
  @ 11,60

  IF Mer:type = " "
    *    end the report function and return to main menu
    RELEASE ALL LIKE Mer*

    ERASE
    USE
    RETURN
  ENDIF

  *    go ahead and report on the employee file...
REMARK    Opening the index file -

  IF Mer:type = '1'
    *   use the name index
    SET index TO e'byname
    ?? "E'BYNAME"
  ELSE
    *   use the nmbr index
    SET index TO e'bynmbr
    ?? "E'BYNMBR"
  ENDIF

  *  if you want to be able to list on a certain criterion this is where you
  * would put the code to ask the user what that criterion should be. It should
  * be put into a memory variable and incorporated in the report statement as
  * as a macro definition.

  *   reuse the last variable used.  Set to assume report to console
  STORE F TO Mer:type

?
? "     The report may be printed on either the console or the printer."
? "         Enter 'P' to print the report on the printer."
? "         Enter 'C' to list the report on the screen."

 *   initialize the variable and accept only 'P' or 'C'
  STORE ' ' TO Mer:type
  SET colon OFF
  DO WHILE .not. Mer:type$'PC'
    @ 19,4 SAY "Enter 'P' or 'C' " GET Mer:type PICTURE '!'
    READ
  ENDDO
  SET colon ON

  STORE ' ' TO Mer:devc
  IF Mer:type='P'
    *   if we are in here, then we must want to list to the printer
    SET console OFF

    REPORT FORM emp-prt TO print

    *  set console back on
    SET console ON
  ELSE
   IF Mer:type='C'
    *   OK, so you want to see the report on the console...
     REPORT FORM emp-cons
     ? 'Press return when ready to view report menu. '

    *    the SET CONSOLE OFF/ON commands will hide the word WAITING from
    *   the screen and leave the cursor at the end of the prompt line
     SET console OFF
     WAIT
     SET console ON
     ?
   endif
  ENDIF    listing routine

ENDDO   doing forever
RETURN

