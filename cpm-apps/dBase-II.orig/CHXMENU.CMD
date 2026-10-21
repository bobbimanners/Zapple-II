* CHXMENU.CMD  MAIN MENU FOR CHECKBOOK MANAGEMENT SYSTEM
* Copyright 1983, Ashton-Tate and RSP, Inc.
* written by Jim Taylor and Wayne Ratliff
*  - turn off display of commands to screen
SET TALK OFF
* PULL RETAINED VARIABLES FROM MEMORY FILE
RESTORE FROM CHXBOOK.MEM
DO WHILE T
* DO WHILE T  means DO WHILE TRUE  I.E. DO FOREVER
*   The DO WHILE will be terminated by a RETURN command
ERASE
  @ 3,20 SAY '       CHECK BOOK MANAGEMENT MENU'
  @ 5,10 SAY 'LAST CHECK #'+STR(LASTCHK,6)
  @ 5,45 SAY 'CURRENT BALANCE $ '+STR(BALANCE,8,2)
  @ 7,10 SAY ' 0 - EXIT'
  @ 9,10 SAY ' 1 - ENTER NEW CHECKS    '
  @ 11,10 SAY ' 2 - ENTER DEPOSITS     '
  @ 13,10 SAY ' 3 - ENTER CANCELLED CHECKS '
  @ 15,10 SAY ' 4 - RECONCILE BANK STATEMENT  '
  @ 17,8 SAY 'ENTER NUMBER OF DESIRED ACTION  0 1 2 3 4'
  *  - reading user response
  WAIT TO ACTION
  * process user's response
  DO CASE
  *  - test for exit condition
    CASE ACTION='0'
       SET TALK ON
       RELEASE ACTION
       * RETAIN VARIABLES
       SAVE TO CHXBOOK
       *  - return to CALLING PROGRAM OR dBASE SYSTEM
       RETURN

  *  - test for new checks
    CASE ACTION='1'
       *  - enter new check data
       * DO CHXNEW
    *  +++++   from here to the next ++++ could be a seperate command file
       * CHXNEW COMMAND FILE TO ENTER NEW CHECKS
       * OPEN DATABASE FILE AND FORMAT FILE
         USE CHECKS
         SET FORMAT TO CHXINPUT.FMT
       * REMEMBER WHERE WE START
         GO BOTTOM
         STORE CHKNO+1 TO FIRSTCHK
         STORE # TO FIRSTREC
       * NOW ADD THE NEW DATA
         APPEND
       * WHEN FINISHED, HOLD ON TO LAST CHECK NUMBER
         STORE CHKNO TO LASTCHK
       * CALCULATE HOW MUCH WE JUST SPENT
         SUM AMT TO SPENT FOR CHKNO >= FIRSTCHK .AND. CHKNO <= LASTCHK
         STORE BALANCE-SPENT TO BALANCE
       * CLOSE OUT OPEN FILES AND VARIABLES
         USE
         SET FORM TO
         RELEASE FIRSTCHK,FIRSTREC,SPENT
       * NEW BALANCE, LASTCHK, AND PROGRAM EXECUTION PASSED BACK TO CHXMENU.CMD
    *   ++++

  *  - test for new deposits
    CASE ACTION='2'
       *  - enter new deposit data
       * OPEN DEPOSITS AND FORMAT FILES
         USE DEPOSITS
         SET FORMAT TO CHXDEPOS.FMT
       * REMEMBER WHERE WE ARE
         GO BOTTOM
         STORE #+1 TO FIRSTDEP
       * ADD THE NEW DATA
         APPEND
       * ADD UP ALL THE NEW DEPOSITS
         SUM AMT TO DEPOSIT FOR #>= FIRSTDEP
         STORE BALANCE+DEPOSIT TO BALANCE
       * CLOSE OUT DEPOSIT ROUTINE
         SET FORM TO
         USE
         RELEASE DEPOSIT,FIRSTDEP
       * NEW BALANCE AND PROGRAM EXECUTION PASSED BACK TO CHXMENU.CMD

  *  - test for cancelled checks
    CASE ACTION='3'
       *  - enter cancelled check data
         USE CHECKS
         STORE T TO MORE
         ERASE
         DO WHILE MORE
         ERASE
         STORE 0 TO C:CAN
         @ 4,5 SAY "CHECK CANCELATION ROUTINE.     "
         @ 11,10 SAY "ENTER 0 TO EXIT "
         @ 12,5 SAY "ENTER CHECK NUMBER TO BE CANCELLED ";
                GET C:CAN PICTURE "####"
         READ
       *  - testing for exit condition
         IF C:CAN=0
            STORE F TO MORE
            LOOP
         ENDIF
       *  - search for cancelled check number
         LOCATE FOR CHKNO=C:CAN
         IF .NOT. CAN .AND. .NOT. EOF
          *  - if not already cancelled or at end of file, display check data
           @ 15,20 SAY 'Paid to '+TRIM(PAYTO)+' on '+DATE
           @ 17,20 SAY 'Amount of check is $'
           @ 17,40 SAY AMT
           @ 19,20 SAY 'for '+MEMO
          *  - ask if this is the right check
           STORE Y TO ANSWER
           @ 21,10 SAY 'Is this the one? (Y/N) ' GET ANSWER
           READ
           IF ANSWER
            *  - change logical flag for cancelled check
             REPLACE CAN WITH T
             @ 21,50 SAY "CANCELLED"
           ENDIF
         ELSE
          *  - message to tell the user that the check is not in file.
           @ 15,5 SAY "Check "+STR(C:CAN,4)+;
                    " cannot be found or is already cancelled."
           ACCEPT "           <cr> to continue " to WAIT
         ENDIF
       ENDDO MORE
       ERASE
       ? "           LIST OF REMAINING UNCLEARED CHECKS "
       ?
       ? "CHKNO       PAID TO                       AMOUNT  DATE         MEMO"
       ?
       DISPLAY OFF ALL FOR .NOT. CAN CHKNO, PAYTO, AMT, DATE, TRIM(MEMO)
       WAIT
       USE
       RELEASE C:CAN, ANSWER, MORE, WAIT
       * NO VARIABLES PASSED BACK TO CHXMENU.CMD

  *  - test for reconcile with bank statement
    CASE ACTION='4'
       *  - compute balances
       * COMMANDS TO RECONCILE BALANCE WITH BANK STATEMENT
        ERASE
        USE CHECKS
        @ 5,5 SAY ' PROGRAM TO RECONCILE WITH BANK STATEMENT '
	@ 8,15 SAY 'CALCULATING BALANCE NOW '
	SUM AMT TO OUTSTAND FOR .NOT. CAN
       *  - display total of outstanding checks
        @ 13,0 SAY 'TOTAL OUTSTANDING CHECKS    = $'
        @ 13,33 SAY OUTSTAND
        STORE 0.00 TO BANK:BAL
       *  - request ending balance from check book
       	@ 15,0 SAY 'ENTER ENDING BALANCE FROM BANK STATEMENT' GET BANK:BAL
	READ
        @ 17,0 SAY 'APPARENT BALANCE = $'
        @ 17,20 SAY BANK:BAL-OUTSTAND
        DO CASE
          CASE BANK:BAL-OUTSTAND > 0
            @ 19,10 SAY 'CHXCANC.CMD WILL LIST UNCLEARED CHECKS '
          CASE BANK:BAL-OUTSTAND = 0
            @ 19,10 SAY 'CHECKS.DBF AND BANK STATEMENT EXACTLY BALANCE '
          CASE BANK:BAL-OUTSTAND < 0
            @ 19,10 SAY 'USE CHXDEPOS.CMD TO ADJUST ACCOUNT FOR INTEREST OR FEES '
            @ 21,10 SAY 'LAST 12 DEPOSITS LISTED HERE '
            USE DEPOSITS
            GO BOTTOM
            SKIP -11
            LIST OFF NEXT 12 DATE,'$',STR(AMT,8,2),PAIDFROM
        ENDCASE
        RELEASE BANK:BAL, OUTSTAND
        USE
        ?
        ? '          ready to return to main menu '
        WAIT
       * NO VARIABLES PASSED BACK TO CHXMENU.CMD

  *  - non-valid entry to the menu and ring bell
    OTHERWISE
       ERASE
       @ 20,5 SAY 'ENTRY MUST BE BETWEEN 0 AND 4 '+CHR(7)
  ENDCASE
ENDDO
RETURN
* EOF CHXMENU.CMD
