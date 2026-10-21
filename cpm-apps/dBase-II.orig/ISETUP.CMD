*  setup the inventory database and index files...
erase
? 'Initializing data files for inventory.'
?
? 'THIS WILL DELETE ALL RECORDS FROM THE INVENTORY FILE....'
ACCEPT 'DO YOU REALLY WANT TO DO THIS (Y/N)?' TO ans
IF !(ans) ='Y'
  use invent
  delete all
  pack
  index on !(prd:desc) TO i'bydesc
  index on !(prd:nmbr) TO i'bynmbr
  do imain
ENDIF
return

 key.  Record # has been set to 0.

NON-NUMERIC EXPRESSION -- SUM command needs a numeric expression to sum.

NOT A dBASE II DATABA