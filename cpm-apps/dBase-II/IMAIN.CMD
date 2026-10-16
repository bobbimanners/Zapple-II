*  01/27/83     for Ashton-Tate    by joe stegman
*     Demonstration Programs   Inventory Maintenance  IMAIN.CMD
*        dBASE II(tm)    release 2.4
*
*  Main control program. Displays a menu and takes appriate action
*
SET talk OFF
CLEAR

STORE T TO clr:scrn
DO WHILE T
 *   ok to clear screen?
  IF clr:scrn
    ERASE
  ENDIF
  STORE " " TO inselect
  SET intensity OFF
  @  2, 7 SAY "Enter one of the following menu selections to begin"
  @  3,10 SAY "your trek through this sample inventory."
  @  6,10 SAY "0    Exit back to dBASE II"
  @  7,10 SAY "1    Add, Change, Delete Inventory items."
  @  8,10 SAY "2    Display inventory quantity"
  @  9,10 SAY "3    Print inventory stock report"

 *   print selection prompt 4 lines down from bottom of menu
  @ $+4, 5 SAY "Enter selection here ?"
  SET colon OFF
  @ $,28 GET inselect PICTURE '9'
  READ
  SET colon ON
  SET intensity ON

 *   erase the error message line
  @ 20,0

 *   reset clr:scrn flag.
  STORE T TO clr:scrn
  DO CASE
    CASE inselect = "0" .or. inselect = " "
       USE
       RELEASE ALL
       RETURN

    CASE inselect = "1"
       DO invmaint

    CASE inselect = "2"
       DO invquan

    CASE inselect = "3"
       DO invrprt

    OTHERWISE

       @ 20,5 SAY "Invalid menu option, please reenter menu selection."

      *  set the clr:scrn flag off...(so we don't ERASE the error msg)
       STORE F TO clr:scrn

    ENDCASE
ENDDO
RETURN
*  eof
