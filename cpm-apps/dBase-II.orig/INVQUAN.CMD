* 01/27/83      for Ashton-Tate   written by joe stegman
*      Demonstration program INVENTORY   INVQUAN.cmd
*
*   Display on hand and on order  inventory quantities
*     also print the inventory prices, cost and extended amounts.

SET talk OFF
ERASE
USE invent
*  test the eof status, at least make sure there is some inventory to display
IF eof
  SET intensity OFF
  @ 1,10 SAY 'There is no inventory in the database.'
ELSE
  @ 1,10 SAY 'Summing up inventory details, please wait'

 *    calculate the totals to be used in the display
  SUM onhand, onordr, prd:pric *onhand, prd:cost *onhand;
   TO Mionhand, Mionordr, Miprdpric, Miprdcost

  STORE (Miprdcost/Miprdpric) * 100.000 TO Miratio

 *   get the number of items in inventory
  GOTO bott
  STORE # to Miitems

  SET inte OFF
  @ 3,3 SAY Miitems USIN  [Number of different products in inventory:  9999]
  @ 4,3 SAY Mionhand USIN [Total number of items in inventory is:      9999]
  @ 5,3 SAY Mionordr USIN [Total number of items on order:             9999]

 *   print dollar totals
  @ 8,3 SAY Miprdcost USING;
     [Total cost of all goods in inventory is:     9,999,999.99]

  @ 9,3 SAY Miprdpric USING;
     [Total price of all inventoried goods is:     9,999,999.99]

  @ 10,3 SAY Miratio USING;
     [Ratio of inventory cost to selling price is:       999.999%]
ENDIF

@ 17,2 SAY [Press >return< when ready for main menu to display]
WAIT
SET intensity ON
@ 18,20
RELEASE ALL LIKE MI*
RETURN
