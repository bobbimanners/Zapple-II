/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *      Rechner und Betriebssystem abhaengige Definitionen
 */
#define LENFN           128     /* max. Laenge von Filenamen */
#define READA           "r"     /* file open mode read ascii */
#define WRITEA          "w"     /* file open mode write ascii */
#define WRITEB          "w"     /* file open mode write binary */

/*
 *	Diverse Konstanten
 */
#define REL             "1.1"
#define COPYR           "Copyright (C) 1988, 89, 90 by Udo Munk"
#define SRCEXT          ".asm"  /* Filenamen-Extension der Quelle */
#define OBJEXT          ".bin"  /* Filenamen-Extension des Object Code */
#define LSTEXT		".lis"	/* Filenamen-Extension des Listings */
#define OUTBIN          1       /* Format der Objektdatei: binaer */
#define OUTMOS          2       /*                         Mostek binaer */
#define OUTHEX          3       /*                         Intel hex */
#define OUTDEF          OUTMOS  /* Default-Format der Objektdatei */
#define COMMENT		';'	/* Kommentar-Zeichen */
#define LINCOM          '*'     /* wenn in Spalte 1, Kommentarzeile */
#define LABSEP		':'	/* Label-Seperator */
#define STRSEP          '\''    /* String-Separator */
#define ENDFILE         "END"   /* Ende der Quelle */
#define MAXFN           512     /* max. Anzahl Quellen */
#define MAXLINE         128     /* max. Laenge einer Zeile Quelle */
#define PLENGTH         65      /* Default Anzahl Zeilen/Seite im Listing */
#define SYMSIZE         8       /* max. Laenge Symbole */
#define INCNEST         5       /* INCLUDE Verschachtelungstiefe */
#define IFNEST          5       /* IF..    Verschachtelungstiefe */
#define HASHSIZE        500     /* Anzahl Eintraege in Symbol-Hash-Array */
#define OPCARRAY        256     /* Groesse des Arrays fuer generierte Ops */
#define SYMINC          100     /* Anfangsgroesse des sortierten Symbol-Array */

/*
 *	Struktur der OP-Code Tabelle
 */
struct opc {
	char *op_name;		/* Op-Code Name */
	int (*op_fun) ();	/* Pointer auf Funktion zur Codeerzeugung */
	int  op_c1;             /* erster Basis-OP-Code */
	int  op_c2;             /* zweiter Basis-OP-Code */
};

/*
 *      Struktur der Operanden Tabelle
 */
struct ope {
	char *ope_name;         /* Operand Name */
	int ope_sym;            /* Symbolischer Wert des Operanden */
};

/*
 *      Struktur der Symbol-Tabelleneintraege
 */
struct sym {
	char *sym_name;		/* Symbol Name */
	int  sym_wert;          /* Symbol Wert */
	struct sym *sym_next;	/* naechster Eintrag */
};

/*
 *      Struktur fuer verschachtelte INCLUDE's
 */
struct inc {
	unsigned inc_line;      /* Zeilenzaehler fuers Listing */
	char *inc_fn;           /* Filename der Datei mit INCLUDE */
	FILE *inc_fp;           /* Filepointer der Datei mit INCLUDE */
};

/*
 *      Definition der Symbole fuer die Operanden.
 *      Die Definitionen fuer Register A, B, C, D, H, L
 *      und (HL) entsprechen den Bits in den Opcodes
 *      und duerfen auf keinen Fall geaendert werden!
 */
#define REGB            0       /* Register B */
#define REGC            1       /* Register C */
#define REGD            2       /* Register D */
#define REGE            3       /* Register E */
#define REGH            4       /* Register H */
#define REGL            5       /* Register L */
#define REGIHL          6       /* Register indirekt HL */
#define REGA            7       /* Register A */
#define REGI            8       /* Register I */
#define REGR            9       /* Register R */
#define REGAF           10      /* Registerpaar AF */
#define REGBC           11      /* Registerpaar BC */
#define REGDE           12      /* Registerpaar DE */
#define REGHL           13      /* Registerpaar HL */
#define REGIX           14      /* Register IX */
#define REGIY           15      /* Register IY */
#define REGSP           16      /* Register SP */
#define REGIBC          17      /* Register indirekt BC */
#define REGIDE          18      /* Register indirekt DE */
#define REGIIX          19      /* Register indirekt IX */
#define REGIIY          20      /* Register indirekt IY */
#define REGISP          21      /* Register indirekt SP */
#define FLGNC           30      /* Flag no carry */
#define FLGNZ           31      /* Flag not zerro */
#define FLGZ            32      /* Flag zerro */
#define FLGM            33      /* Flag minus */
#define FLGP            34      /* Flag plus */
#define FLGPE           35      /* Flag parrity even */
#define FLGPO           36      /* Flag parrity odd */
#define NOOPERA         98      /* kein Operand vorhanden */
#define NOREG           99      /* Operand ist kein Register */

/*
 *      Definition der Assembler-Fehler-Nummern, die
 *      zu Fehlermeldungen im Listfile fuehren
 *      (siehe asmerr)
 */
#define E_ILLOPC        0       /* illegaler Opcode */
#define E_ILLOPE        1       /* illegaler Operand */
#define E_MISOPE        2       /* fehlender Operand */
#define E_MULSYM        3       /* mehrfach definiertes Symbol */
#define E_UNDSYM        4       /* undefiniertes Symbol */
#define E_VALOUT        5       /* Wert ausserhalb Bereich */
#define E_MISPAR        6       /* Klammer fehlt */
#define E_MISHYP        7       /* String Separator fehlt */
#define E_MEMOVR        8       /* memory override (ORG) */
#define E_MISIFF        9       /* fehlendes IF bei ELSE oder ENDIF */
#define E_IFNEST        10      /* IF zu tief verschachtelt */
#define E_MISEIF        11      /* fehlendes ENDIF */
#define E_INCNEST       12      /* INCLUDE zu tief verschachtelt */

/*
 *      Definition der Fehlernummern, die zum sofortigen
 *      Abbruch des Programms fuehren (siehe fatal)
 */
#define F_OUTMEM        0       /* out of memory */
#define F_USAGE         1       /* usage: .... */
#define F_HALT          2       /* Assembly halted */
#define F_FOPEN         3       /* can't open file */
#define F_INTERN        4       /* internal error */
