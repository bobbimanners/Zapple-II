* 01/27/83
*   Inventory entry routine
*   ASHTON-TATE
*   joe stegman
*
*   program prompts for the inventory items
*      allows  ADDs, CHANGEs, and DELETEs
*
SET talk OFF
USE invent INDEX i'bynmbr, i'bydesc
SET index TO i'bynmbr, i'bydesc
ERASE
*   Set up the format for the work screen
SET intensity OFF
@  1, 0 SAY "+-------------------------------------------------"
@  1,50 SAY "-----------------------------+"
store 2 to line
do while line < 18
  @ line, 0 SAY "|"
  @ line,79 SAY "|"
  store line +1 to line
enddo
@ 3,0 SAY "+-------------------------------------------------"
@ 3,50 SAY "-----------------------------+"
@ 18, 0 SAY "+-------------------------------------------------"
@ 18,50 SAY "-----------------------------+"
SET intensity ON

*   initialize delete flag
STORE F TO Midelete

STORE T TO Miwork
DO WHILE Miwork

  SET intensity OFF
  @ 2,24 SAY 'Inventory Maintenance Screen'
  @ 20,6 SAY 'To add a new item to inventory enter a new item number.'
  @ 21,6 SAY 'To edit an item in inventory enter that item number.'
  @ 22,6 SAY 'Press return to display the main menu.'
  SET intensity ON

  STORE "      " TO Miprdnmbr
  @  8,18 SAY "Product number"
  @  8,42 GET Miprdnmbr PICTURE '!!!!!!'
  READ

  @ 19,0
  @ 20,0
  @ 21,0
  @ 22,0
  STORE TRIM(Miprdnmbr) TO Miprdnmbr
  DO CASE        *Main level 0

   *    do this case if there was a product number entered...
    CASE Miprdnmbr > " "
   *   look for the product nmbr
     FIND "&Miprdnmbr"

     SET intensity OFF
     DO CASE        *test record type
      CASE #=0
       *   didn't find the product,  so find out if an item is to be added 
        @ 19,10 SAY [Product number &Miprdnmbr not on database file.]
        STORE F TO Mi:ok
        SET intensity OFF
        @ 21,6 SAY [Would you like to add the item to the database (Y/N) ? ]
        @ 21,$+1 GET Mi:ok
        READ
        SET intensity ON
        @ 19,0
        @ 21,0
        IF Mi:ok
         *   initialize the temporary memory variables
          STORE '                    ' TO Miprddesc
          STORE 0.00 TO Miprdprc, Miprdcst
          STORE 0 TO Mionhand, Mionordr
          STORE "N" TO Mie:ok
          @ 2,24 SAY "    Enter new inventory item  "
         *   read the new inventory info
          DO invread
          @ 23,2 SAY 'working'
        ENDIF
        RELEASE Mi:ok
       *

      CASE *
       *    '*' means deleted,  do they still want it to be deleted?
        @ 19,10 SAY [Product &Miprdnmbr is marked for deletion]
        STORE F TO Mi:ok
        SET intensity ON
        @ 21,7 SAY [Do you want to recall the item (Y/N) ? ]
        SET intensity OFF
        SET colon OFF
        @ 21,$+1 GET Mi:ok
        SET colon ON
        READ
        @ 19,0
        IF Mi:ok
         *    no, guess they decided it should still be in the inventory
          RECALL
          @ 19,10 SAY [Product number &Miprdnmbr recalled from deletion.]
        ENDIF
        @ 21,0

      CASE #>0
       *  display the record found and ask user what to do.
        SET intensity ON
        @  9,18 SAY "Description"
        @  9,42 SAY prd:desc
        @ 10,18 SAY "Unit Cost"
        @ 10,42 SAY prd:cost
        @ 11,18 SAY "Sell price"
        @ 11,42 SAY prd:pric
        @ 12,18 SAY "Number items in stock"
        @ 12,43 SAY onhand
        @ 13,18 SAY "Number itmes on order"
        @ 13,43 SAY onordr

        SET colon OFF
        STORE ' ' TO Mivar
        DO WHILE .not. Mivar$"CD/"
          @ 21,10 SAY [Enter (C)hange, (D)elete, >/< to skip ? ]
          @ 21,42 GET Mivar PICTURE "!"
          READ
        ENDDO
        SET colon ON
        SET intensity OFF
        @ 19,0
        @ 21,10 SAY '                                                         '

        IF Mivar = 'C'
         *   set up item in memory variables for update
          STORE prd:nmbr TO Miprdnmbr
          STORE prd:desc TO Miprddesc
          STORE prd:pric TO Miprdprc
          STORE prd:cost TO Miprdcst
          STORE onhand TO Mionhand
          STORE onordr TO Mionordr
          STORE "N" TO Mie:ok
          @ 2,24 SAY "    Update inventory item       "
          DO invread
          @ 23,3 SAY 'working'
        ELSE
          IF Mivar = 'D'
           * ok by user to delete record. so doit
           DELETE
           STORE T TO Midelete
           @ 19,10 SAY [Product number &Miprdnmbr is marked for deletion.]
          ENDIF     mivar = 'c'
         ENDIF     mivar = 'd'

    ENDCASE      *level 1
    SET intensity ON
    @  9,18 SAY '                                              '
    @ 10,18 SAY '                                 '
    @ 11,18 SAY '                                 '
    @ 12,18 SAY '                              '
    @ 13,18 SAY '                              '
    @ 23,0 SAY '                                        '
  OTHERWISE
    STORE F TO Miwork
  ENDCASE      *level 0

ENDDO

IF Midelete
  SET intensity OFF
  @ 8,18 SAY 'Packing and re-indexing database file'
  SET intensity ON
 *   pack and reindex the file using the current index keys
  PACK
ENDIF

RELEASE ALL LIKE Mi*
RETURN
