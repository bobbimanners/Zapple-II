* Program.: DATESYS.CMD
* Author..: Luis A. Castro. 
* Date....: 12/6/82. 
* Notice..: Copyright 1982,  ASHTON-TATE. 
* Notes...: To set the system date with a verified date using
*   the DATETEST subroutine. This command file works only with
*   dBASE II version 2.3B and 2.4 under CP/M 2.2. You may want
*   to remove all the comment lines, if you want to make this
*   program run faster.
*
* Subroutine DATETEST:
*   Memory used.: A410H to A482H.
*   Description.: Checks date input, entered through POKEs to
*      locations 41997,41998, and 41999.  Location 41997 gets the
*      month parameter, location 41998 gets the day, and location
*      41999 gets the year.  Returns nulls at locations 41997,
*      41998, and 41999 if there is an error in input.  This 
*      subroutine also checks for leap year.
*   Note........: This subroutine will always be available through
*      a POKE and CALL command once it is loaded, as long as you
*      do not execute a SORT command.
*
* Disclaimer: This program is a sample program. The author does 
*   not claim it to be syntactically correct or complete.  The
*   author recommends that the user always maintain backup files,
*   especially when trying a new program.  Any corruption of data
*   resulting from the use of this program is the sole respon-
*   sibility of the user. 
*
SET TALK OFF 
SET BELL OFF
SET INTENSITY OFF 

STORE DATE() TO mdate
IF mdate="00/00/00"
   * The POKE sequences that follow, load the DATETEST
   * subroutine starting at address 42000 decimal.
   * I chose the POKE method, because with small
   * subroutines it is faster than LOADing.
   SET CALL TO 42000 
   *             0   1   2   3   4   5   6   7   8   9 
   POKE 42000,  58, 14,164,254,  1,218,115,164,254, 32 
   POKE 42010, 210,115,164, 58, 15,164,254,  0,218,115 
   POKE 42020, 164,254,100,210,115,164, 58, 13,164,254 
   POKE 42030,   1,218,115,164,254, 13,210,115,164,254 
   POKE 42040,   2,202, 92,164, 14,  4, 33,127,164,190 
   POKE 42050,  35,202, 83,164, 13,194, 65,164, 58, 14 
   POKE 42060, 164,254, 32,210,115,164,201, 58, 14,164 
   POKE 42070, 254, 31,210,115,164,201, 58, 15,164,230 
   POKE 42080,   3, 58, 14,164,202,109,164,254, 29,210 
   POKE 42090, 115,164,201,254, 30,210,115,164,201, 62 
   POKE 42100,   0, 50, 13,164, 50, 14,164, 50, 15,164 
   POKE 42110, 201,  4,  6,  9, 11 

   * Next, a prompt is displayed on the screen to get
   * the date and the program loops through until a 
   * valid date is entered.
   ERASE
   @ 2, 0 SAY 'S Y S T E M    D A T E'
   @ 3, 0 SAY '========================================'
   @ 3,40 SAY '========================================'

   * Initialize the date parameters...
   POKE 41997,0,0,0

   DO WHILE PEEK(41997)=0
      STORE "  /  /  " TO mdate
      @ 5,0 SAY 'Enter system date as MM/DD/YY ';
            GET mdate PICTURE "99/99/99"
      READ
      * Now POKE the month,day, and year into 
      * locations 41997,41998,and 41999 respectively.  
      POKE 41997,VAL($(mdate,1,2))
      POKE 41998,VAL($(mdate,4,2))
      POKE 41999,VAL($(mdate,7,2))
      CALL
   ENDDO

   * If you prefer an input format of DD/MM/YY you would
   * substitute the above DO WHILE..ENDDO with
   *
   * DO WHILE PEEK(41997)=0
   *    STORE "  /  /  " TO mdate
   *    @ 5,0 SAY 'Enter system date as DD/MM/YY ';
   *          GET mdate PICTURE "99/99/99"
   *    READ
   *    POKE 41997,VAL($(mdate,4,2))
   *    POKE 41998,VAL($(mdate,1,2))
   *    POKE 41999,VAL($(mdate,7,2))
   *    CALL
   * ENDDO

   * The system date is set at this point.
   SET DATE TO &mdate
ENDIF

RETURN 
* EOF DATESYS.CMD 
