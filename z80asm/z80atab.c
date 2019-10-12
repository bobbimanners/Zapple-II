/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *	Dieses Modul enthaelt alle Operationen, die die
 *	Tabellen durchsuchen oder veraendern.
 */

#include <stdio.h>
#include "z80a.h"
#include "z80aglb.h"

/*	Die folgende Funktion fuehrt die binaere Suche
 *	in der alphabetisch sortierten OP-Code-Tabelle
 *	'opctab' aus.
 *
 *      Input:  Zeiger auf String mit dem OP-Code
 *
 *      Output: Zeiger auf das Tabellenelement oder
 *              einen NULL-Pointer, wenn OP-Code
 *              nicht gefunden
 */
struct opc *search_op(op_name)
register char *op_name;
{
	register int cond;
	register struct opc *low, *high, *mid;

	low = &opctab[0];
	high = &opctab[no_opcodes - 1];
	while (low <= high) {
		mid = low + (high - low) / 2;
		if ((cond = strcmp(op_name, mid->op_name)) < 0)
			high = mid - 1;
		else if (cond > 0)
			low = mid + 1;
		else
			return(mid);
	}
	return(NULL);
}

/*	Die folgende Funktion fuehrt die binaere Suche
 *      in der alphabetisch sortierten Operanden-Tabelle
 *      'opetab' aus.
 *
 *      Input:  Zeiger auf String mit dem Operanden
 *
 *      Output: Symbol fuer den Operanden
 *              NOOPERA, wenn Operand leer ist
 *              NOREG, wenn Operand nicht gefunden
 */
get_reg(s)
register char *s;
{
	register int cond;
	register struct ope *low, *high, *mid;

	if (s == NULL || *s == '\0')
		return(NOOPERA);
	low = &opetab[0];
	high = &opetab[no_operands - 1];
	while (low <= high) {
		mid = low + (high - low) / 2;
		if ((cond = strcmp(s, mid->ope_name)) < 0)
			high = mid - 1;
		else if (cond > 0)
			low = mid + 1;
		else
			return(mid->ope_sym);
	}
	return(NOREG);
}

/*	Die folgende Funktion fuehrt die Suche in der Symboltabelle
 *	'symtab' durch. Dazu wird ein HASH-Algorithmus verwendet.
 *
 *      Input:  Zeiger auf String mit dem Symbol
 *
 *      Output: Zeiger auf das Tabellenelement oder
 *              einen NULL-Pointer, wenn Symbol
 *              nicht gefunden
 */
struct sym *get_sym(sym_name)
register char *sym_name;
{
	register struct sym *np;

	for (np = symtab[hash(sym_name)]; np != NULL; np = np->sym_next)
		if (strcmp(sym_name, np->sym_name) == 0)
			return(np);
	return(NULL);
}

/*	Die folgende Funktion traegt ein Symbol in die Symboltabelle
 *      'symtab' ein. Ist das Symbol in der Tabelle noch nicht
 *      vorhanden, wird es neu angelegt, sonst wird 'sym_wert'
 *      in den vorhandenen Eintrag uebernommen.
 *	Fuer die Symboltabellen-Zugriffe wird ein HASH-Algorithmus
 *	verwendet.
 *
 *	Input:	sym_name Zeiger auf String mit dem Symbol
 *		sym_wert Wert des Symbols
 *
 *      Output: 0 = eingetragen
 *              1 = kein Speicherplatz mehr frei
 */
put_sym(sym_name, sym_wert)
char *sym_name;
int sym_wert;
{
	char *strsave(), *malloc();
	struct sym *get_sym();
	register int hashval;
	register struct sym *np;

	if (!gencode)
		return(0);
	if ((np = get_sym(sym_name)) == NULL) {
		np = (struct sym *) malloc(sizeof (struct sym));
		if (np == NULL)
			return(1);
		if ((np->sym_name = strsave(sym_name)) == NULL)
			return(1);
		hashval = hash(sym_name);
		np->sym_next = symtab[hashval];
		symtab[hashval] = np;
	}
	np->sym_wert = sym_wert;
	return(0);
}

/*
 *      Diese Funktion traegt ein Label in die Symboltabelle ein.
 *      Vorher wird geprueft, ob dieses Symbol bereits vorhanden
 *      ist, was zu einer entsprechenden Fehlermeldung fuehrt.
 */
put_label()
{
	struct sym *get_sym();

	if (get_sym(label) == NULL) {
		if (put_sym(label, pc))
			fatal(F_OUTMEM, "symbols");
	} else
		asmerr(E_MULSYM);
}

/*	Hier folget der HASH-Algorithmus selbst.
 *
 *      Input:  Zeiger auf String mit dem Namen
 *
 *      Output: HASH-Wert
 */
hash(name)
register char *name;
{
	register int hashval;

	for (hashval = 0; *name;)
		hashval += *name++;
	return(hashval % HASHSIZE);
}

/*	Diese Funktion kopiert einen String auf einen
 *	angeforderten Speicherplatz.
 *
 *      Input:  Zeiger auf den String
 *
 *      Output: Zeiger auf den Speicherplatz
 */
char *strsave(s)
register char *s;
{
	char *malloc(), *strcpy();
	register char *p;

	if ((p = malloc((unsigned) strlen(s)+1)) != NULL)
		strcpy(p, s);
	return(p);
}

/*
 *      Diese Funktion kopiert alle Eintraege aus der
 *      Symbol-Hashtabelle in ein dynamisch erzeugtes
 *      Pointer-Array
 */
copy_sym()
{
	char *malloc(), *realloc();
	register int i, j;
	register struct sym *np;

	symarray = (struct sym **) malloc(SYMINC * sizeof(struct sym *));
	if (symarray == NULL)
		fatal(F_OUTMEM, "sorting symbol table");
	symsize = SYMINC;
	for (i = 0, j = 0; i < HASHSIZE; i++) {
		if (symtab[i] != NULL) {
			for (np = symtab[i]; np != NULL; np = np->sym_next) {
				symarray[j++] = np;
				if (j == symsize) {
					symarray = (struct sym **) realloc((char *) symarray, symsize * sizeof(struct sym *) + SYMINC * sizeof(struct sym *));
					if (symarray == NULL)
						fatal(F_OUTMEM, "sorting symbol table");
					symsize += SYMINC;
				}
			}
		}
	}
	return(j);
}

/*
 *      Symboltabelle nach Namen sortieren
 */
n_sort_sym(len)
register int len;
{
	register int gap, i, j;
	register struct sym *temp;

	for (gap = len/2; gap > 0; gap /= 2)
		for (i = gap; i < len; i++)
			for (j = i-gap; j >= 0; j -= gap) {
				if (strcmp(symarray[j]->sym_name, symarray[j+gap]->sym_name) <= 0)
					break;
				temp = symarray[j];
				symarray[j] = symarray[j+gap];
				symarray[j+gap] = temp;
			}
}

/*
 *      Symboltabelle nach Adressen sortieren
 */
a_sort_sym(len)
register int len;
{
	register int gap, i, j;
	register struct sym *temp;

	for (gap = len/2; gap > 0; gap /= 2)
		for (i = gap; i < len; i++)
			for (j = i-gap; j >= 0; j -= gap) {
				if (numcmp(symarray[j]->sym_wert, symarray[j+gap]->sym_wert) <= 0)
					break;
				temp = symarray[j];
				symarray[j] = symarray[j+gap];
				symarray[j+gap] = temp;
			}
}

/*
 *      Vergleicht zwei 16-Bit Werte, Ergebnis wie strcmp
 */
numcmp(n1, n2)
register int n1, n2;
{
	if ((unsigned) (n1 & 0xffff) < (unsigned) (n2 & 0xffff))
		return(-1);
	else if ((unsigned) (n1 & 0xffff) > (unsigned) (n2 & 0xffff))
		return(1);
	else
		return(0);
}
