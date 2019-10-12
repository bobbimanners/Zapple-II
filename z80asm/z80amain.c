/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

#include <stdio.h>
#include <ctype.h>
#include "z80a.h"
#include "z80aglb.h"

static char *errmsg[] = {               /* Fehlermeldungen fuer fatal() */
	"out of memory: %s",            /* 0 */
	"usage: z80asm -ofile -f[b|m|h] -l[file] -s[n|a] -v -dsymbol ... file ...",
	"Assembly halted",              /* 2 */
	"can't open file %s",           /* 3 */
	"internal error: %s"            /* 4 */
};

main(argc, argv)
int argc;
char *argv[];
{
	int len;

	init();
	options(argc, argv);
	printf("Z80 - Assembler Release %s, %s\n", REL, COPYR);
	pass1();
	pass2();
	if (list_flag) {
		switch (sym_flag) {
		case 0:         /* keine Symboltabelle */
			break;
		case 1:         /* unsortierte Symboltabelle */
			lst_sym();
			break;
		case 2:         /* nach Namen sortierte Symboltabelle */
			len = copy_sym();
			n_sort_sym(len);
			lst_sort_sym(len);
			break;
		case 3:         /* nach Adressen sortierte Symboltabelle */
			len = copy_sym();
			a_sort_sym(len);
			lst_sort_sym(len);
			break;
		default:
			break;
		}
		fclose(lstfp);
	}
	return(errors);
}

/*
 *	Initialisierung
 */
init()
{
	errfp = stdout;
}

/*
 *	Diese Funktion bearbeitet die beim Aufruf angegebenen Options.
 *      Die uebergebenen Dateinamen werden in die entsprechenden
 *	Strings uebernommen.
 */
options(argc, argv)
int argc;
char *argv[];
{
	register char *s, *t;
	register int i;
	char *malloc();

	while (--argc > 0 && (*++argv)[0] == '-')
		for (s = argv[0]+1; *s != '\0'; s++)
			switch (*s) {
			case 'o':
			case 'O':
				if (*++s == '\0') {
					puts("name missing in option -o");
					usage();
				}
				get_fn(objfn, s, OBJEXT);
				s += (strlen(s) - 1);
				break;
			case 'l':
			case 'L':
				if (*(s + 1) != '\0') {
					get_fn(lstfn, ++s, LSTEXT);
					s += (strlen(s) - 1);
				}
				list_flag = 1;
				break;
			case 's':
			case 'S':
				if (*(s + 1) == '\0')
					sym_flag = 1;
				else if ((*(s + 1) == 'n') || (*(s + 1) == 'N'))
					sym_flag = 2;
				else if ((*(s + 1) == 'a') || (*(s + 1) == 'A'))
					sym_flag = 3;
				else {
					printf("unknown option -%s\n", s);
					usage();
				}
				s += (strlen(s) - 1);
				break;
			case 'f':
			case 'F':
				if ((*(s + 1) == 'b') || (*(s + 1) == 'B'))
					out_form = OUTBIN;
				else if ((*(s + 1) == 'm') || (*(s + 1) == 'M'))
					out_form = OUTMOS;
				else if ((*(s + 1) == 'h') || (*(s + 1) == 'H'))
					out_form = OUTHEX;
				else {
					printf("unknown option -%s\n", s);
					usage();
				}
				s += (strlen(s) - 1);
				break;
			case 'd':
			case 'D':
				if (*++s == '\0') {
					puts("name missing in option -d");
					usage();
				}
				t = tmp;
				while (*s)
					*t++ = islower(*s) ? toupper(*s++) : *s++;
				s--;
				*t = '\0';
				if (put_sym(tmp, 0))
					fatal(F_OUTMEM, "symbols");
				break;
			case 'v':
			case 'V':
				ver_flag = 1;
				break;
			default :
				printf("unknown option %c\n", *s);
				usage();
			}
	i = 0;
	while ((argc--) && (i < MAXFN)) {
		if ((infiles[i] = malloc(LENFN + 1)) == NULL)
			fatal(F_OUTMEM, "filenames");
		get_fn(infiles[i], *argv++, SRCEXT);
		i++;
	}
	if (i == 0) {
		printf("no input file given\n");
		usage();
	}
}

/*
 *	An den Argumenten in der Befehlszeile ist was falsch,
 *	Gebrauchsanleitung ausgeben und abbrechen.
 */
usage()
{
	fatal(F_USAGE, NULL);
}

/*
 *	Fehlermeldung ausgeben und abbrechen
 */
fatal(i, arg)
register int i;
register char *arg;
{
	void exit();

	printf(errmsg[i], arg);
	putchar('\n');
	exit(1);
}

/*
 *	Pass 1:
 *	  - Lauf ueber alle Quelldateien
 */
pass1()
{
	register int fi;

	pass = 1;
	pc = 0;
	fi = 0;
	if (!ver_flag)
		puts("Pass 1");
	open_o_files(infiles[fi]);
	while (infiles[fi] != NULL) {
		if (!ver_flag)
			printf("   Read    %s\n", infiles[fi]);
		p1_file(infiles[fi]);
		fi++;
	}
	if (errors) {
		fclose(objfp);
		unlink(objfn);
		printf("%d error(s)\n", errors);
		fatal(F_HALT, NULL);
	}
}

/*
 *	Pass 1:
 *	  - Lauf ueber eine Quelldatei
 *
 *      Input:  Name der zu bearbeitenden Quelldatei
 */
p1_file(fn)
char *fn;
{
	c_line = 0;
	srcfn = fn;
	if ((srcfp = fopen(fn, READA)) == NULL)
		fatal(F_FOPEN, fn);
	while (p1_line())
		;
	fclose(srcfp);
	if (iflevel)
		asmerr(E_MISEIF);
}

/*
 *	Pass 1:
 *	  - Eine Zeile Quelle verarbeiten
 *
 *      Output: 1 Zeile verarbeitet
 *              0 EOF erreicht
 */
p1_line()
{
	register char *p;
	register int i;
	register struct opc *op;
	char *get_label(), *get_opcode(), *get_arg();
	struct opc *search_op();

	if ((p = fgets(line, MAXLINE, srcfp)) == NULL)
		return(0);
	c_line++;
	p = get_label(label, p);
	p = get_opcode(opcode, p);
	p = get_arg(operand, p);
	if (strcmp(opcode, ENDFILE) == 0)
		return(0);
	if (*opcode) {
		if ((op = search_op(opcode)) != NULL) {
			i = (*op->op_fun)(op->op_c1, op->op_c2);
			if (gencode)
				pc += i;
		} else
			asmerr(E_ILLOPC);
	} else
		if (*label)
			put_label();
	return(1);
}

/*
 *	Pass 2:
 *        - Lauf ueber alle Quelldateien
 */
pass2()
{
	register int fi;

	pass = 2;
	pc = 0;
	fi = 0;
	if (!ver_flag)
		puts("Pass 2");
	obj_header();
	while (infiles[fi] != NULL) {
		if (!ver_flag)
			printf("   Read    %s\n", infiles[fi]);
		p2_file(infiles[fi]);
		fi++;
	}
	obj_end();
	fclose(objfp);
	printf("%d error(s)\n", errors);
}

/*
 *      Pass 2:
 *	  - Lauf ueber eine Quelldatei
 *
 *      Input:  Name der zu bearbeitenden Quelldatei
 */
p2_file(fn)
char *fn;
{
	c_line = 0;
	srcfn = fn;
	if ((srcfp = fopen(fn, READA)) == NULL)
		fatal(F_FOPEN, fn);
	while (p2_line())
		;
	fclose(srcfp);
}

/*
 *      Pass 2:
 *	  - Eine Zeile Quelle verarbeiten
 *
 *      Output: 1 Zeile verarbeitet
 *              0 EOF erreicht
 */
p2_line()
{
	register char *p;
	register int op_count;
	register struct opc *op;
	char *get_label(), *get_opcode(), *get_arg();
	struct opc *search_op();

	if ((p = fgets(line, MAXLINE, srcfp)) == NULL)
		return(0);
	c_line++;
	s_line++;
	p = get_label(label, p);
	p = get_opcode(opcode, p);
	p = get_arg(operand, p);
	if (strcmp(opcode, ENDFILE) == 0) {
		lst_line(pc, 0);
		return(0);
	}
	if (*opcode) {
		op = search_op(opcode);
		op_count = (*op->op_fun)(op->op_c1, op->op_c2);
		if (gencode) {
			lst_line(pc, op_count);
			obj_writeb(op_count);
			pc += op_count;
		} else {
			sd_flag = 2;
			lst_line(0, 0);
		}
	} else {
		sd_flag = 2;
		lst_line(0, 0);
	}
	return(1);
}

/*
 *	Oeffnen der Ausgabedateien: Objectdatei und bei Option
 *	-l der Listdatei. Der Dateiname der Quelldatei wird 
 *	uebergeben. Die Dateinamen der Object- und Listdatei
 *	werden, wenn nicht hinter den Optionen -l und -o angegeben,
 *	aus dem Quelldateinamen erzeugt.
 */
open_o_files(source)
register char *source;
{
	char *strcpy(), *strcat(), *strrchr();
	register char *p;

	if (*objfn == '\0')
		strcpy(objfn, source);
	if ((p = strrchr(objfn, '.')) != NULL)
		strcpy(p, OBJEXT);
	else
		strcat(objfn, OBJEXT);

	if (out_form == OUTHEX)
		objfp = fopen(objfn, WRITEA);
	else
		objfp = fopen(objfn, WRITEB);
	if (objfp == NULL)
		fatal(F_FOPEN, objfn);
	if (list_flag) {
		if (*lstfn == '\0')
			strcpy(lstfn, source);
		if ((p = strrchr(lstfn, '.')) != NULL)
			strcpy(p, LSTEXT);
		else
			strcat(lstfn, LSTEXT);
		if ((lstfp = fopen(lstfn, WRITEA)) == NULL)
			fatal(F_FOPEN, lstfn);
		errfp = lstfp;
	}
}

/*
 *	Einen Dateinamen in "dest" aus "src" und "ext" zusammenbauen
 */
get_fn(dest, src, ext)
char *dest, *src, *ext;
{
	char *strrchr(), *strcat();
	register int i;
	register char *sp, *dp;

	i = 0;
	sp = src;
	dp = dest;
	while ((i++ < LENFN) && (*sp != '\0'))
		*dp++ = *sp++;
	*dp = '\0';
	if ((strrchr(dest,'.') == NULL) && (strlen(dest) <= (LENFN-strlen(ext))))
		strcat(dest, ext);
}

/*
 *	Extrahieren der Labels, Konstanten und Variablen aus
 *	einer Zeile Quelltext mit Umwandlung in Grosschrift
 *	und Begrenzung der Laenge.
 */
char *get_label(s, l)
register char *s, *l;
{
	register int i;

	i = 0;
	if (*l == LINCOM)
		goto comment;
	while (!isspace(*l) && *l != COMMENT && *l != LABSEP && i < SYMSIZE) {
		*s++ = islower(*l) ? toupper(*l++) : *l++;
		i++;
	}
comment:
	*s = '\0';
	return(l);
}

/*
 *	Extrahieren des Op-Codes aus einer Zeile Quelltext ab der
 *	uebergebenen Position. Der String wird bei der Uebertragung
 *	in Grosschrift umgewandelt.
 */
char *get_opcode(s, l)
register char *s, *l;
{
	if (*l == LINCOM)
		goto comment;
	while (!isspace(*l) && *l != COMMENT && *l != LABSEP)
		l++;
	if (*l == LABSEP)
		l++;
	while (*l == ' ' || *l == '\t')
		l++;
	while (!isspace(*l) && *l != COMMENT)
		*s++ = islower(*l) ? toupper(*l++) : *l++;
comment:
	*s = '\0';
	return(l);
}

/*
 *	Extrahieren des Operanden aus einer Zeile Quelltext ab der
 *	uebergebenen Position. Der String wird bei der Uebertragung
 *      in Grosschrift umgewandelt und Blanks sowie Tabs werden
 *      ueberlesen. Strings, die in ' eingeschlossen sind, werden
 *      ohne Aenderung kopiert.
 */
char *get_arg(s, l)
register char *s, *l;
{
	if (*l == LINCOM)
		goto comment;
	while (*l == ' ' || *l == '\t')
		l++;
	while (*l != '\n' && *l != COMMENT) {
		if (isspace(*l)) {
			l++;
			continue;
		}
		if (*l != STRSEP) {
			*s++ = islower(*l) ? toupper(*l) : *l;
			l++;
			continue;
		}
		*s++ = *l++;
		if (*(s - 2) == 'F')    /* EX AF,AF' !!!!! */
			continue;
		while (*l != STRSEP) {
			if (*l == '\n' || *l == '\0' || *l == COMMENT)
				goto comment;
			*s++ = *l++;
		}
		*s++ = *l++;
	}
comment:
	*s = '\0';
	return(l);
}
