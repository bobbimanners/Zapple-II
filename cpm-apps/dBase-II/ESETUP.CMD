* 03/03/83  ESETUP.CMD
*   Copyright (c) 1983      ASHTON-TATE
*   Programmed by joe stegman  for dBASE II(tm) release 2.4
*
*  employee sample programs database setup program
*   calls  EMAIN.cmd
set talk off
? '  Initializing the employee database and memory files.'
?
? 'THIS WILL DESTORY ALL EMPLOYEE RECORDS!!!'
ACCEPT 'IS THIS WHAT YOU WANT TO DO (Y/N) ?' TO ANS
IF !(ans) ='Y'
  use employee
  delete all
  pack
  index on !(trim(first)) +' '+ !(trim(last)) to e'byname
  index on emp:nmbr to e'bynmbr
  store 0 to Memp:nmbr
  save to employee
  rele all
  ?
  ?
  ? 'Loading employee main menu program.'
  do emain
endif
return


"TO" PHRASE NOT FOUND -- Rewrite command with correct syntax.

TOO MANY CHARACTERS -- Non-Full-Screen only.  Data entered exceeds 
        allotted length of field.

TOO MANY FILES ARE OPEN -- Only 16 files of all types (Command, .FMT, .NDX) 
        may be open at one time.

TOO MANY MEMORY VARIABLES -- There is a maximum of 64 memory variables.