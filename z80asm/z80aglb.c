/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *	Dieses Modul enthaelt alle globalen Variablen des
 *      Assemblers, ausser der CPU spezifischen Tabellen.
 */

#include <stdio.h>
#include "z80a.h"

char *infiles[MAXFN],		/* Filenamen aller Quellen */
     objfn[LENFN + 1],		/* Filename des Object Code */
     lstfn[LENFN + 1],		/* Filename des Listing */
     *srcfn,                    /* Filename der gerade bearbeiteten Quelle */
     line[MAXLINE],		/* Puffer fuer eine Zeile Quelle */
     tmp[MAXLINE],              /* termoraerer Puffer */
     label[SYMSIZE+1],		/* Puffer fuer extrahiertes Label */
     opcode[MAXLINE],		/* Puffer fuer extrahierten Op-Code */
     operand[MAXLINE],          /* Puffer fuer extrahierten Operanden */
     ops[OPCARRAY],             /* Puffer fuer generierten Op-Code */
     title[MAXLINE];            /* Puffer fuer Titel der Quelle */

int  list_flag,			/* Flag fuer Option -l */
     sym_flag,                  /* Flag fuer Option -s */
     ver_flag,                  /* Flag fuer Option -v */
     pc,                        /* Programm-Counter */
     pass,			/* Momentaner Durchlauf */
     iflevel,                   /* aktuelle Verschachtelungstiefe der IF's */
     gencode = 1,               /* Flag fuer conditional Codegenerierung */
     errors,                    /* Zaehler fuer errors */
     errnum,                    /* Fehler Nummer in Pass 2 */
     sd_flag,                   /* List-Flag fuer PSEUDO Op-Codes */
				/* = 0: Adresse aus <val>, Daten aus <ops> */
				/* = 1: Adresse aus <sd_val>, Daten aus <ops> */
				/* = 2: keine Adresse, Daten aus <ops> */
				/* = 3: Adresse aus <sd_val>, keine Daten */
				/* = 4: ganze Zeile unterdruecken */
     sd_val,                    /* Ausgabewert fuer PSEUDO Op-Codes */
     prg_adr,                   /* Startadresse des Programms */
     prg_flag,                  /* Flag fuer prg_adr gueltig */
     out_form = OUTDEF,         /* Format der Objektdatei */
     symsize;                   /* Groesse von symarray */

FILE *srcfp,			/* Filepointer fuer aktuelle Quelle */
     *objfp,			/* Filepointer fuer Object Code */
     *lstfp,			/* Filepointer fuer Listing */
     *errfp;			/* Filepointer fuer Fehler */
				/* abhaengig von -l lstfp oder stdout */

unsigned c_line,		/* aktuelle Zeile der aktuellen Quelle */
	 s_line,                /* Zeilenzaehler fuers Listing */
	 p_line,                /* Anzahl gedruckter Zeilen auf der Seite */
	 ppl = PLENGTH,         /* Anzahl Zeilen/Seite */
	 page;                  /* Seitenzaehler fuer Listing */

struct sym *symtab[HASHSIZE],   /* Symboltabelle */
	   **symarray;          /* sortierte Symboltabelle */
