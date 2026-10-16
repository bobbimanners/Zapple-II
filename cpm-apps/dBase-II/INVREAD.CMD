* 12.82
*   Inventory read data routine
*   ASHTON-TATE
*   joe stegman
*
*   Set up the screen for input, the memory variables are set up by the
*    INVMAINT program which has decided whether this is an add or a change...
*

DO WHILE Mie:ok = "N"
 *  setup the screen and read the data from the user
  @  9,18 SAY "Description"
  @  9,42 GET Miprddesc
  @ 10,18 SAY "Unit Cost"
  @ 10,42 GET Miprdcst PICTURE '999.99'
  @ 11,18 SAY "Sell price"
  @ 11,42 GET Miprdprc PICTURE '999.99'
  @ 12,18 SAY "Number items in stock"
  @ 12,42 GET Mionhand PICTURE '999'
  @ 13,18 SAY "Number itmes on order"
  @ 13,42 GET Mionordr PICTURE '999'
  READ

 *  is all the info correct?
  @ 20, 2 SAY [Is the inventory information correct (Y-yes, N-no, A-abort) ?]
 *  accept only Y - N or A for a user response
  SET colon OFF
  STORE " " TO Mie:ok
  DO WHILE .not. Mie:ok$'YNA'
     @ 20,64 GET Mie:ok PICTURE '!'
     READ
  ENDDO
  SET colon ON
  @ 20,0
  @ 22,0
ENDDO

IF Mie:ok = "Y"
 *  if the record pointer is at record zero, then this is probably an ADD
  IF #=0
   *  ah ha...   adding a new record... since the find was not successfull
    APPEND BLANK
  ENDIF
 *   now save the inventory info in the database
  REPLACE prd:nmbr WITH Miprdnmbr, prd:desc WITH Miprddesc
 *  remember NOUPDATE skips checking for index keys(faster update)
  REPLACE prd:cost WITH Miprdcst, prd:pric WITH Miprdprc NOUPDATE
  REPLACE onhand WITH Mionhand, onordr WITH Mionordr NOUPDATE
ENDIF

RELEASE ALL LIKE miprd*
RELEASE ALL LIKE mion*
RETURN
