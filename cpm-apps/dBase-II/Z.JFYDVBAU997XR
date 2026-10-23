* 03/02/83   for Ashton-Tate   by joe stegman
*   demonstration programs Employee Termination,  EMP-TERM.CMD
*      for dBASE II(tm)   release 2.4
*    This is command file may be changed and enhanced to fit your application
*
*    Here is where we are going to select employees for termination.
*    We need to know the name of the employee to terminate and the
*     date of termination... I don't think that we will ever really
*     remove the employee from the database. Not even as far as marking
*     for deletion.
*
*    Local variables begin with 'Met'
*    Called from EMAIN.CMD
*    Uses EMPLOYEE.DBF
*         E'BYNAME.NDX
*         E'BYNMBR.NDX

SET talk OFF
*  open the database file
USE employee
ERASE
DO WHILE T

  @ 0,0 SAY ' '
  TEXT
     To select an employee for termination, enter the employee
          number or the employee name(First Last).

     To view the main menu enter a single >return<.
  ENDTEXT
  @ 6,0
  @ 5,0 SAY ' '
  ACCEPT  'Enter employee data for termination ? ' TO Met:srch
  STORE !(Met:srch) TO Met:srch

  IF Met:srch = ' '
    *  time to return to the menu, Release the local var., clear the screen
    RELEASE ALL LIKE Meu*
    ERASE
    *  close the database file, and return to the menu
    USE
    RETURN
  ENDIF

  *   initialize the record found variable
  STORE F TO Met:recfnd

  IF VAL(Met:srch) > 0
    *   it must be an employee number.
    SET index TO e'bynmbr
    *    have to make the search string 3 characters for the find
    *      becuase the index key is STR(emp:name,3)
    STORE STR(VAL(Met:srch),3) TO Met:srch
    *   have to put the macro within quotes because of leading spaces...
    FIND '&Met:srch'
    IF #=0
      *   no record was found for the employee number entered
      @ 20,5 SAY 'Employee number not found. Please try another.'
    ELSE
      *   since a record was found for the search data.  set a flag TRUE
      STORE T TO Met:recfnd
    ENDIF
  ELSE
    *   the search data must be an employee name...
    SET index TO e'byname
    FIND &Met:srch
    IF #=0
      *   must not be anybody on the file with the name used for the search
      @ 20,5 SAY 'Employee name is not on the file.'
      ? '      You may correct the name and try again.'
    ELSE
      *   the employee name is on the file. so set up for the edit...
      STORE T TO Met:recfnd
    ENDIF
  ENDIF

  *   if the record was found then edit it.
  IF Met:recfnd
    ERASE
   *   display employee data...
    SET colon OFF
    DO emp-upd.fmt
    SET colon ON
    Clear gets

    STORE '  /  /  ' TO Met:tdate
    STORE F TO Met:ok
    DO WHILE .not. Met:ok
      @ 20,10 SAY "Please enter termination date, or return to keep active ? ";
           GET Met:tdate PICTURE '99/99/99'
      READ
      IF Met:tdate > '  /  /  '
       *    assume date is ok.
        STORE T TO Met:ok
        CALL Met:tdate
        IF Met:tdate = '   '
         *     too bad, date has an error.. reset loop variable
          @ 15,40 SAY "** Invalid Terminate Date **'
          STORE F TO Met:ok
        ENDIF     met:date > '   '
      ELSE     termdate is blank    i.e. do not mark for deletion
        STORE T TO Met:ok
      ENDIF    termdate = '  /  /  '
    ENDDO    when date is ok
   *    using replace with NOUPDATE, skips checking the index, much faster
    REPLACE termdate WITH Met:tdate NOUPDATE
    ERASE
  ENDIF    Met:recfnd... terminate test

ENDDO     loop until program is ended
*   program should never really get this far.
quit
