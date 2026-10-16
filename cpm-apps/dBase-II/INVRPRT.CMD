*   12.82
*   Ashton-Tate
*   by joe stegman
*
*   Print the invoice detail to a printer
*

ERASE
SET intensity OFF
@  2,10 SAY "Printing inventory detail report."
@  4, 5 SAY "Enter 'N' to print report in item number sequence"
@  5, 5 SAY "   or 'D' for the report printed by description"
@  6, 5 SAY "   enter report sequence (N/D) ? "

SET colon OFF
STORE ' ' TO Mir:type
DO WHILE .not. Mir:type$'DN'
   @  6,38 GET Mir:type PICTURE '!'
   READ
ENDDO
SET colon ON

*   assume report by item number
SET index TO i'bynmbr
SET heading TO 'by item number'
IF Mir:type = 'D'
   SET index TO i'bydesc
   SET heading TO 'by item description'
ENDIF

SET colon OFF
STORE ' ' TO Mir:type
@ 8,5 SAY 'Enter report destination (C)onsole, (P)rinter'
DO WHILE .NOT. Mir:type $ "PC"
   @ 8,51 GET Mir:type PICTURE '!'
   READ
ENDDO

*   initialize device macro variable
IF Mir:type = 'P'
  REPORT FORM inv'prtr TO print
ELSE
  REPORT FORM inv'cons
  ? 'Press >return< to display main menu.'
  *   the next code sement make dBASE wait for user to press return.
  *      but notice that the word 'WAITING' does not display.
  SET cons OFF
  WAIT
  SET cons ON
ENDIF

SET intensity ON
RELEASE Mir:type
RETURN
