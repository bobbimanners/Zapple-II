* Program.: LABELS.CMD
* Author..: Luis A. Castro.
* Date....: 9/15/82.
* Notice..: Copyright 1982,  ASHTON-TATE.
* Notes...: To print mailing labels more than one across without
*   printing a blank line when the company field is blank.
*   You may want to remove all the comment lines, if you want
*   to make this program run faster. Uses a data file with
*   the following structure:
*       NAME,C,<number>
*       COMPANY,C,<number>
*       ADDRESS,C,<number>
*       CITY,C,<number>
*       STATE,C,<number>
*       ZIP,C,<number>
*
* References: 
*   You will notice that I use macro substitution extensively
*   in this program (i.e., using the ampersand (&) symbol).
*   You will want to look in your manual for documentation on
*   this command.
*
SET TALK OFF
SET BELL OFF
SET INTENSITY OFF

* Initialize macros...
STORE "TRIM(city)+', '+TRIM(state)+'  '+TRIM(zip)" TO Macro
STORE "line1+$(blank,1,column*gap-LEN(line1))" TO Mline1 
STORE "line2+$(blank,1,column*gap-LEN(line2))" TO Mline2
STORE "line3+$(blank,1,column*gap-LEN(line3))" TO Mline3
STORE "line4+$(blank,1,column*gap-LEN(line4))" TO Mline4

* Initialize memory variables...
* The expression "$(STR(0,133),1,132)" is a tricky way of 
* initializing 132 blanks to memory variables.
STORE $(STR(0,133),1,132) TO blank,line1,line2,line3,line4
STORE "NAMES" TO filename
STORE 1 TO nacross
STORE " " TO select
STORE 25 TO gap
STORE "Y" TO printer

ERASE
* Heading is displayed and parameters are entered...
@ 2,29 SAY "PRINT MAILING LABELS"
@ 3,29 SAY "--------------------"
@ 5,20 SAY "Enter number of labels to go across ";
       GET nacross PICTURE "9"
@ 6,25 SAY "Enter gap between columns ";
       GET gap PICTURE "99"
READ

* Minimum and maximum values are tested...
IF gap < 25
   STORE 25 TO gap
ENDIF
IF nacross > 4
   STORE 4 TO nacross
ENDIF

* At this point a prompt is displayed to allow the user
* to send output to the screen or printer.
SET COLON OFF
@ 8,15 SAY "Do you want to send output to the printer? (Y/N) ";
       GET printer PICTURE "!"
READ
@ 9,17 SAY "When labels are in place, hit carriage return ";
       GET select
READ
SET COLON ON
ERASE

USE &filename
DO WHILE .NOT. EOF

   * Store first column to output lines...
   STORE TRIM(name) TO line1
   IF company=" "
      STORE TRIM(address) TO line2
      STORE &Macro TO line3
      STORE " " TO line4
   ELSE
      STORE TRIM(company) TO line2
      STORE TRIM(address) TO line3
      STORE &Macro TO line4
   ENDIF

   * Store rest of columns to output lines...
   IF nacross > 1
      SKIP
   ENDIF
   STORE 1 TO column
   DO WHILE .NOT. EOF .AND. column < nacross
      STORE &Mline1+TRIM(name) TO line1
      IF company=" "
         STORE &Mline2+TRIM(address) TO line2
         STORE &Mline3+&Macro TO line3
      ELSE
         STORE &Mline2+TRIM(company) TO line2
         STORE &Mline3+TRIM(address) TO line3
         STORE &Mline4+&Macro TO line4
      ENDIF
      STORE column+1 TO column
      IF column < nacross
         SKIP
      ENDIF
   ENDDO while .not.eof.and.column<across

   * We are now ready to display (or print) the
   * contents of memory variables line1 thru line4.
   IF printer = "Y"
      SET CONSOLE OFF
      SET PRINT ON
   ENDIF
   ? line1
   ? line2
   ? line3
   ? line4
   ?
   ?
   IF printer="Y"
      SET PRINT OFF
      SET CONSOLE ON
   ENDIF

   SKIP
ENDDO while .not.eof

?
? "THAT'S ALL FOLKS..."
CLEAR
RETURN
* EOF labels.cmd
