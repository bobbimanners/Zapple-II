* Program...: DATER.CMD
* Author(s).: "UNKNOWN", modified by Luis A. Castro.
* Date......: 1/12/83. 
* Notice....: Copyright 1983, ASHTON-TATE 
* Notes.....: Demonstrates converting from calendar date
*   to julian date, adding a given number of days, then 
*   converting back to the calendar date.

SET TALK OFF 
SET BELL OFF 
SET INTENSITY OFF 
ERASE
@ 2, 0 SAY "C A L E N D A R - J U L I A N    C O N V E R S I O N"
@ 3, 0 SAY "========================================"
@ 3,40 SAY "========================================"

STORE "        " TO mdate
DO WHILE mdate="  "
   STORE "        " TO mdate
   @ 5,0 SAY 'Enter calendar date ';
         GET mdate PICTURE "99/99/99"
   READ
   STORE VAL($(mdate,1,2)) TO month
   STORE VAL($(mdate,4,2)) TO day
   STORE VAL($(mdate,7,2))+1900 TO year
   * If you wish to verify the date and the DATESYS
   * command file has been executed, type the following:
   *   POKE 41997,month,day,year
   *   CALL
ENDDO

* Convert from CALENDAR to JULIAN...
* What is 395.25???
STORE INT(30.57*month)+INT(365.25*year-395.25)+day TO julian
* Adjust the julian date if leap year...
IF month > 2
   IF INT(year/4) = year/4
      STORE julian-1 TO julian
   ELSE
      STORE julian-2 TO julian
   ENDIF
ENDIF
@ 6, 0 SAY "The julian date is ="
@ 6,20 SAY julian
STORE 0 TO delta
@ 8,0 SAY "Enter interval in days between dates ";
       GET delta PICTURE "999"
READ
STORE julian+delta TO mjulian

* Convert from JULIAN to CALENDAR...
STORE INT(mjulian/365.26)+1 TO year
STORE mjulian+INT(395.25-365.25*year) TO day
* Calculate extra day for leap year...
IF INT(year/4)*4 = year
   STORE 1 TO leapday
ELSE
   STORE 2 TO leapday
ENDIF
* Calculate actual number of days...
IF day > (91-leapday)
   STORE day+leapday TO day
ENDIF
* Generate actual month, day, and year...
STORE INT(day/30.57) TO month
STORE day-INT(30.57*month) TO day
IF month > 12
   STORE 1 TO month
   STORE year+1 TO year
ENDIF

* Set-up the calendar date and display it...
STORE year-1900 TO year
STORE STR(month,2)+"/"+STR(day,2)+"/"+STR(year,2) TO mdate
@ 10,0 SAY "CALENDAR DATE = "+mdate

RELEASE leapday,mdate,julian,mjulian,day,month,year,delta
RETURN 
* EOF dater.cmd
