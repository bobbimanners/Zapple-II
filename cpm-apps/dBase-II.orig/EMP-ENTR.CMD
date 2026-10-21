*  01/24/83  for Ashton-Tate    by joe stegman
*    Demonstration program EMPLOYEE ADD.  EMP-ENTR.CMD
*
*  Employee entry routine...  use the empscrn format screen as the entry format
*
*   the employee file should aslo be indexed on the dept+class+employee name
*   this will allow the employee data to be reported in that order
*
*   this sample program uses a format screen in conjunction with the edit
*  command for entering the employee data.
*
*  Local memory variables for the function start with >Mea:<
*  Called from EMAIN.CMD
*   Uses EMPLOYEE.DBF    Holds the employee data
*        E'BYNAME.NDX    Index on !(trim(FIRST))+' '+!(trim(LAST))
*        E'BYNMBR.NDX    Index on emp:nmbr
*        EMPSCRN.FMT     format file for screen entry
*        EMPLOYEE.MEM    Holds the last employee number.
*
SET talk OFF
*  restore the employee number from a memory file.
RESTORE FROM employee
*
*   Open the data and index files.
USE employee INDEX e'byname, e'bynmbr

*  do until no more employees to add
STORE T TO Meawork
DO WHILE Meawork

  ERASE
  IF Meawork
    STORE Memp:nmbr +1 TO Memp:nmbr
    APPEND BLANK
   *    this will save the employee number and also update the index
    REPLACE emp:nmbr WITH Memp:nmbr
    *   save the record number to edit
    STORE STR(#,4) TO Mea:newrec
    STORE F TO Mea:ok

    DO WHILE .not. Mea:ok
     *  open the format file and read the employee data.
      SET format TO empscrn
      READ
     *   set the format beck to screen for screen updates
      SET format TO screen
      *  test the hire date for validity
      STORE hiredate TO Mea:date
      STORE T TO Mea:nodate
      DO WHILE Mea:nodate
       *   if we get here the hire date was not valid, so try again.
        STORE F TO Mea:nodate
        CALL Mea:date
        IF Mea:date = '        '
          @ 14,40 SAY '** Invalid Hire Date **'
          @ 14,10 SAY "Hire date"
          @ 14,21 GET Mea:date PICTURE '99/99/99'
          READ
          STORE T TO Mea:nodate
        ENDIF
      ENDDO
      SET colon OFF
      @ 14,40
      @ 22,0 SAY "Is the employee data correct (Y/N)? " GET Mea:ok
      READ
      SET colon ON
      @ 22,0
     *   make sure we set up the current pay rate from the starting pay
      REPLACE payrate WITH start:pay, hiredate WITH Mea:date NOUPDATE
    ENDDO
  ENDIF    meawork

 *   Find out if more employees should be added
  STORE F TO Meawork
  @ 22,0 SAY "Want to add another employee (Y/N)? " GET Meawork
  READ
 *   now clear the prompt line
  @ 22,0
ENDDO   when not adding any more employees

*   Close the database and index files
USE
*   release local variables
RELEASE ALL LIKE Mea*
*   save the new employee number
SAVE TO employee
*   since EMAIN dosent clear the screen when we return,  we do it here
ERASE
RETURN
*  eof EMP-ENTR.cmd
*  Called from EMAIN.cmd
lly shouldn't do that again."
      @ 21,3 say '  Why not try a selection between zero and four.'

  ENDCASE
  @ 22,0
ENDDO
RETURN
*   EOF

tal