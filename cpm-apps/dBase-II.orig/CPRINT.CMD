*  Program     CPRINT.cmd     01 March 1983
*    COPYRIGHT (c) 1983       ASHTON-TATE
*    Programmed by joe stegman  for dBASE II(tm) release 2.4
*    Called from CMAIN.cmd

*    This program will print tickle cards from the TEXT database file.
*    The sequence of the report is based on the index in use when this command
*     file is executed. If sequence is by KEYWORD then the user is prompted to
*     enter a keyword to FIND, then a range of dates to print for the keyword.
*    If the TICKLE.ndx file is set then the user will be prompted for a range
*     of dates to print. Then all cards falling within that range will be
*     printed.

*  clear menu from screen
 @ 18,0
 @ 19,0
 @ 20,0
 @ 21,0
 @ 22,0
*   erase the prompt line
 @ 23,0 SAY '                                 '
*   initialize the KEYWORD expression used in the report command
 STORE ' ' TO expression,lkup
 STORE # TO rec:no
 IF .not. tklindex
  *   Printing report based on a keyword
   STORE '.and. !(KEYWORD) = lkupkey' TO expression
   STORE '          ' TO lkupkey
   STORE F TO ok
   DO WHILE .not. ok
     STORE T TO ok
     STORE '          ' TO lkupkey
     @ 19,0 SAY 'Enter keyword to report on, or (/) to exit ';
          GET lkupkey PICT '!!!!!!!!!!'
     READ
     IF lkupkey='/'
       rele expression, lkupkey, ok, lkup
       return
     ENDIF
     FIND '&lkupkey'
     @ 19,55
     IF #=0
       @ 19,55 SAY '** Keyword Not Found **'
       STORE F TO ok
     ENDIF
   ENDDO
 ENDIF
*   read the dates...  But only if the user wants to continue
*  or  if the index is set to the tickle index.

*  set the index to tickle to test for a valid date entry
 set index to tickle,keyword
 STORE '  /  /  ' TO strtdate,stopdate
 STORE F TO ok
 DO WHILE .not. ok
   STORE T TO ok
   @ 21,0 SAY 'Enter Start date for range of cards to print ';
         GET strtdate PICT '99/99/99'
   READ
   IF strtdate='  /  /  '
    *  time to return to cmain
     RELE startdate,stopdate,lkupdate,lkupkey,ok
     RETURN
   ENDIF
   STORE $(strtdate,7,2) +$(strtdate,1,2) +$(strtdate,4,2) TO lkupdate
   FIND &lkupdate
   IF #=0
     @ 21,55 SAY '** Date Not In Index'
     STORE F TO ok
   ENDIF
 ENDDO
*   get the stop date for the range
 STORE strtdate TO stopdate
 STORE F TO ok
 DO WHILE .not. ok
   STORE T TO ok
   @ 22,0 SAY 'Enter Stop date of range of cards to print ';
         GET stopdate PICT '99/99/99'
   read
   IF stopdate < strtdate
     @ 22,55 SAY '** Date Invalid **'
     STORE F TO ok
   ENDIF
 ENDDO
*
 STORE ' ' TO DVC
 DO WHILE .NOT. DVC$'PS'
   @ 23,0 SAY 'Want report to P)rinter or to S)creen. Enter P/S ?';
      GET dvc PICT '!'
   READ
 ENDDO
 STORE " " TO dest
 IF DVC='P'
   STORE 'TO PRINT' TO dest
 ENDIF

 IF .not. tklindex
  *  looking in the Keyword index file
   SET index TO keyword,tickle
*  STORE lkupkey+lkupdate TO lkupkey
   FIND &lkupkey
   LOCATE next 65535 for tkl:date >= strtdate .and. !(keyword)=lkupkey
 ELSE
   FIND &lkupdate
 ENDIF
 REPORT FORM tickle WHILE tkl:date <= stopdate &expression &dest
ENDIF

IF dvc='S'
  ACCEPT 'Press RETURN to display the main menu ' TO dvc
ENDIF
RELE expression, lkupkey, ok, lkup, strtdate, stopdate, dest, dvc, lkupdate
RETURN
*  eof cprint.cmd
