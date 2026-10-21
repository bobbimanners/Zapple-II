BBC BASIC (Z80) version 5.00 Test Package
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you have a genuine Z80 CP/M system you can extract the file BBCBASIC.COM
from the archive and run it on that platform.  However please note that the
cursor and other editing functions are unlikely to work, and if you use the
INKEY() function with a non-zero parameter the time-out won't be functional,
nor will the TIME function work (there is no standard CP/M timer interrupt).

If you have a BBC Micro or BBC Master with Z80 Second Processor (either real
hardware or emulated) you can extract the file BBCTUBE.COM from the archive
and run it on that platform.  All the functions of the native OS should be
available, including graphics and sound.  In the case of the BBC Master 128
there are additional features such as extended graphics (circle and ellipse
plotting, rectangle copy/move, flood fill) and the real-time clock (TIME$).

If you don't have a suitable Z80 CP/M system on which to run the interpreter
a CP/M emulator for Windows is included.  Extract the entire contents of the
Zip archive and run 'runcpm' to run the emulator.  This will start up at the
A0> CP/M prompt; BBC BASIC will be found on the emulated B: drive so type B:
followed by the Enter key to switch to the B: drive, and then type BBCBASIC
<Enter> to run the interpreter (these CP/M commands are not case-sensitive).

The file WHATSNEW.TXT (which can be read in CP/M using the TYPE command, or
in Windows) lists the new features in BBC BASIC (Z80) version 5.00 compared
with version 3.00.  There are also a few BASIC test programs included.
