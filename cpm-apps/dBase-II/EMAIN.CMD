* 01/24/83   Employee Main Menu program  EMAIN.CMD
*     for ASHTON-TATE  by joe stegman
*
* this is where we find what is supposed be done by the user. All we do is
* display a menu of selections which the user may make. When a selection is
* made we try to match it to a function. If no match is made then an error
* message is displayed and we ask for the selection again. If we do find a
* match we execute the code for that match, on return we start over with the
* selection menu again.
*
SET talk OFF
SET call TO 42240
LOAD datetest
*    open the database

ERASE
DO WHILE T
  *     do forever or until T is set to false..  (hehe)
  @ 2,0
  TEXT
 This is the employee data managment program.

     This set of employee management programs allow one to add, edit, list
  and terminate employees from a database. To perform one those functions
  enter one the menu options.

        0     End program and return to dBASE II
        1     Enter new employees
        2     Make changes to employee records
        3     List the employee data
        4     Terminate an employee or two


   Enter the menu selection here
  ENDTEXT
  WAIT TO Mselect

  *   erase the error message line. just in case one was printed
  @ 20,0
  @ 21,0

  DO CASE

    CASE Mselect = "0"
     *    close employee file, release all variables and return to dBASE II
      USE
      RELEASE ALL
      RETURN

    CASE Mselect = "1"
     *   enter some ne employees
      DO emp-entr

    CASE Mselect = "2"
     *   make changes to employee data
      DO emp-upd

    CASE Mselect = "3"
     *   list the employee data.  But we will have to find out what to list
      DO emp-rprt

    CASE Mselect = "4"
     *   oh! too bad somebody gets to be terminated
      DO emp-term

    OTHERWISE
      erase
      @ 20,3 SAY "That felt good, but you really shouldn't do that again."
      @ 21,3 say '  Why not try a selection between zero and four.'

  ENDCASE
  @ 22,0
ENDDO
RETURN
*   EOF

tal