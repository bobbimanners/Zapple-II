* 01/24/83  for Ashton-Tate   by joe stegman
*  Demonstration program Employee Update.  EMP-UPD.CMD
*        for dBASE II(tm)   release 2.4
*
*   Update employee records  via full screen edit
*     Program will display total number of records in database and ask
*  user to enter the name or the employee number of an employee to edit.
*  The employee record will be edited using full screen edit.
*
*
*   Called from EMAIN.CMD
*   LOCAL VARIABLES BEGIN WITH ^MEU^
*   Uses files EMPLOYEE.DBF
*              E'BYNAME.NDX   Indexed on !(trim(first))+' '+!(trim(last))
*              E'BYNMBR.NDX   Indexed on emp:nmbr
*              EMP-UPD.fmt    Format file used to format screen for update
*
USE EMPLOYEE

SET talk OFF
ERASE
DO WHILE T

 *    Be sure to display the text on line one of the screen
  @ 0,0
  TEXT
 You may edit any employee in the database. To select an employee for
edit, enter the employee name(First Last) or the employee number.

  ENDTEXT
 *  the next two lines adjust the cursor so the ACCEPT will print on line 5
 * this works because after dBASE II clears a line, the cursor scroll to the
 * next line of the screen.
  @ 5,0
  @ 4,0 SAY ' '
  ACCEPT  'Enter search data ' TO Meu:srch

 *   erase the error message line
  @ 21,0

  IF Meu:srch = ' '
    *  time to return to the menu, Clear all local variabls, erase the screen
    RELEASE ALL LIKE Meu*
    ERASE
    USE
    *  and return...
    RETURN
  ENDIF

  *   initialize the record found variable
  STORE F TO Meu:recfnd
  *   position the cursor, so that the following messages don't print
  *   at the bottom of the screen
  @ 15,0

  IF VAL(Meu:srch) > 0
    *   Mue:srch must be an employee number.
remark     OK. It looks like an employee number was enetered,
remark so open the E'BYNMBR index and FIND the number
    SET index TO e'bynmbr, e'byname
    *    have to make the search string 3 characters for the find
    *      becuase the index key is STR(emp:name,3)
    STORE STR(VAL(Meu:srch),3) TO Meu:srch
    *   have to put the macro within quotes because of leading spaces...
    FIND '&Meu:srch'
    IF #=0
      *   no record was found for the employee number entered
      @ 21,5 SAY 'Employee number not found. Please try another.'
    ELSE
     *   Ahh! search data was found. Be sure to remember that we found it
      STORE STR(#,4) TO Meu:rnmbr
      STORE T TO Meu:recfnd
    ENDIF
  ELSE
    *   the search data must be an employee name...
REMARK     Well, it seems that what we have is an employee name.
REMARK  opening the E'BYNAME index, FINDing the name says...
    SET index TO e'byname, e'bynmbr
    STORE !(Meu:srch) TO Meu:srch
    FIND &Meu:srch
    IF #=0
      *   must not be anybody on the file with the name used for the search
      @ 21,5 SAY 'Employee name is not on the file.'
      ? '      You may correct the name and try again.'
    ELSE
      *   the employee name is on the file. so set up for the edit...
      STORE T TO Meu:recfnd
      STORE STR(#,4) TO Meu:rnmbr
    ENDIF
  ENDIF

  *   if the record was found then edit it.
  DO WHILE Meu:recfnd
    *   use EMP-UPD.FMT to format the entry screen
     SET format TO emp-upd
     READ
     SET format TO screen
     SET intensity OFF

      *   test the hire date for validity until MEU:DATEOK is TRUE
     STORE hiredate TO Meu:dte

     STORE F TO Meu:dateok
     DO WHILE .not. Meu:dateok
      *   assume date will be ok
       STORE T TO Meu:dateok
      *   call our assembly date checker.
       CALL Meu:dte
       IF Meu:dte = '        '
         @ 14,40 SAY '** Invalid Hire Date **'
         @ 14,10 SAY "Date hired"
         @ 14,21 GET Meu:dte PICTURE '99/99/99'
         READ
         STORE F TO Meu:dateok
       ENDIF
     ENDDO
     @ 14,40
      * test the termination date for validity if entered.
     IF termdate > '  /  /  '
       STORE termdate TO Meu:dte
       STORE F TO Meu:dateok
       DO WHILE .not. Meu:dateok
         STORE T TO Meu:dateok
         CALL Meu:dte
         IF Meu:dte = '        '
           @ 15,40 SAY "** Invalid Terminate Date **'
           @ 15,10 SAY "Terminated"
           @ 15,21 GET Meu:dte PICTURE '99/99/99'
           READ
           STORE F TO Meu:dateok
         ENDIF
       ENDDO
     ENDIF
     @ 15,40
     RELEASE Meu:dte,Meu:dateok
    *
     SET colon OFF
     @ 22,0 SAY 'Are all the changes correct (Y/N) ? ' GET Meu:recfnd
     READ

     SET colon ON
     SET intensity ON
    *    store the negative of the response so that a true response will
    *   will exit the do loop
     STORE .not. Meu:recfnd TO Meu:recfnd
     ERASE
  ENDDO
ENDDO
*   release the local variables
RELEASE ALL LIKE Meu*
ERASE
RETURN
* eof  EMP-UPD.cmd
*   called from EMAIN.cmd
