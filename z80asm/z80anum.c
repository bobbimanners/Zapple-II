/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *      Dieses Modul enthaelt die numerischen
 *      Rechen- und Umwandlungsfunktionen.
 */

#include <stdio.h>
#include <ctype.h>
#include "z80a.h"
#include "z80aglb.h"

#ifndef isxdigit
#define isxdigit(c) (isdigit(c) || (c>='a' && c<='f') || (c>='A' && c<='F'))
#endif

/*
 *      Definition Operatoren-Symbole fuer den Expression-Parser
 */
#define OPEDEC          1       /* Dezimalzahl */
#define OPEHEX          2       /* Hexzahl */
#define OPEOCT          3       /* Octalzahl */
#define OPEBIN          4       /* Binaerzahl */
#define OPESUB          5       /* arithmetisches - */
#define OPEADD          6       /* arithmetisches + */
#define OPEMUL          7       /* arithmetisches * */
#define OPEDIV          8       /* arithmetisches / */
#define OPEMOD          9       /* arithmetisches Modulo */
#define OPESHL          10      /* logisches shift left */
#define OPESHR          11      /* logisches shift right */
#define OPELOR          12      /* logisches OR */
#define OPELAN          13      /* logisches AND */
#define OPEXOR          14      /* logisches XOR */
#define OPECOM          15      /* logisches Komplement */
#define OPESYM          99      /* Symbol */

/*
 *      Rekursiver Expression-Parser
 *
 *	Input:	Pointer auf den restlichen Argument-String
 *
 *      Output: berechneter Wert
 */
eval(s)
register char *s;
{
	register char *p;
	register int val;
	char word[MAXLINE];
	struct sym *sp, *get_sym();

	val = 0;
	while (*s) {
		p = word;
		if (*s == '(') {
			s++;
			while (*s != ')') {
				if (*s == '\0') {
					asmerr(E_MISPAR);
					goto eval_break;
				}
				*p++ = *s++;
			}
			*p = '\0';
			s++;
			val = eval(word);
			continue;
		}
		if (*s == STRSEP) {
			s++;
			while (*s != STRSEP) {
				if (*s == '\n' || *s == '\0') {
					asmerr(E_MISHYP);
					goto hyp_error;
				}
				*p++ = *s++;
			}
			s++;
hyp_error:
			*p = '\0';
			val = strval(word);
			continue;
		}
		if (isari(*s))
			*p++ = *s++;
		else
			while (!isspace(*s) && !isari(*s) && (*s != '\0'))
				*p++ = *s++;
		*p = '\0';
		switch (get_type(word)) {
		case OPESYM:                    /* Symbol */
			if (strcmp(word, "$") == 0) {
				val = pc;
				break;
			}
			if (strlen(word) > SYMSIZE)
				word[SYMSIZE] = '\0';
			if ((sp = get_sym(word)) != NULL)
				val = sp->sym_wert;
			else
				asmerr(E_UNDSYM);
			break;
		case OPEDEC:                    /* Dezimalzahl */
			val = atoi(word);
			break;
		case OPEHEX:                    /* Hexzahl */
			val = axtoi(word);
			break;
		case OPEBIN:                    /* Binaerzahl */
			val = abtoi(word);
			break;
		case OPEOCT:                    /* Oktalzahl */
			val = aotoi(word);
			break;
		case OPESUB:                    /* arithmetisches - */
			val -= eval(s);
			goto eval_break;
		case OPEADD:                    /* arithmetisches + */
			val += eval(s);
			goto eval_break;
		case OPEMUL:                    /* arithmetisches * */
			val *= eval(s);
			goto eval_break;
		case OPEDIV:                    /* arithmetisches / */
			val /= eval(s);
			goto eval_break;
		case OPEMOD:                    /* arithmetisches Modulo */
			val %= eval(s);
			goto eval_break;
		case OPESHL:                    /* logisches shift left */
			val <<= eval(s);
			goto eval_break;
		case OPESHR:                    /* logisches shift right */
			val >>= eval(s);
			goto eval_break;
		case OPELOR:                    /* logisches OR */
			val |= eval(s);
			goto eval_break;
		case OPELAN:                    /* logisches AND */
			val &= eval(s);
			goto eval_break;
		case OPEXOR:                    /* logisches XOR */
			val ^= eval(s);
			goto eval_break;
		case OPECOM:                    /* logisches Komplement */
			val = ~(eval(s));
			goto eval_break;
		}
	}
	eval_break:
	return(val);
}

/*
 *      Operanden Typ-Bestimmung
 *
 *      Input:  Pointer auf zu bestimmenden String
 *
 *      Output: Operanden Typ
 */
get_type(s)
char *s;
{
	if (isdigit(*s)) {              /* numerischer Operand */
		if (isdigit(*(s + strlen(s) - 1)))      /* Dezimalzahl */
			return(OPEDEC);
		else if (*(s + strlen(s) - 1) == 'H')   /* Hexzahl */
			return(OPEHEX);
		else if (*(s + strlen(s) - 1) == 'B')   /* Binaerzahl */
			return(OPEBIN);
		else if (*(s + strlen(s) - 1) == 'O')   /* Oktalzahl */
			return(OPEOCT);
	} else if (*s == '-')           /* arithmetischer Operand - */
		return(OPESUB);
	else if (*s == '+')             /* arithmetischer Operand + */
		return(OPEADD);
	else if (*s == '*')             /* arithmetischer Operand * */
		return(OPEMUL);
	else if (*s == '/')             /* arithmetischer Operand / */
		return(OPEDIV);
	else if (*s == '%')             /* arithmetisches Modulo */
		return(OPEMOD);
	else if (*s == '<')             /* logisches shift left */
		return(OPESHL);
	else if (*s == '>')             /* logisches shift rigth */
		return(OPESHR);
	else if (*s == '|')             /* logisches OR */
		return(OPELOR);
	else if (*s == '&')             /* logisches AND */
		return(OPELAN);
	else if (*s == '^')             /* logisches XOR */
		return(OPEXOR);
	else if (*s == '~')             /* logisches Komplement */
		return(OPECOM);
	return(OPESYM);                 /* Operand ist ein Symbol */
}

/*
 *      Die Funktion prueft einen Character auf die arithmetischen
 *      Operatoren +, -, *, /, %, <, >, |, &, ~ und ^.
 */
isari(c)
register int c;
{
	return((c) == '+' || (c) == '-' || (c) == '*' ||
	       (c) == '/' || (c) == '%' || (c) == '<' ||
	       (c) == '>' || (c) == '|' || (c) == '&' ||
	       (c) == '~' || (c) == '^');
}

/*
 *      Umwandlung eines ASCII-Strings mit einer Hexzahl in
 *      einen Integer.
 *      Format: nnnnH oder 0nnnnH wenn 1.Ziffer > 9
 */
axtoi(str)
register char *str;
{
	register int num;

	num = 0;
	while (isxdigit(*str)) {
		num *= 16;
		num += *str - ((*str <= '9') ? '0' : '7');
		str++;
	}
	return(num);
}

/*
 *      Umwandlung eines ASCII-Strings mit einer Oktalzahl in
 *      einen Integer.
 *      Format: nnnnO
 */
aotoi(str)
register char *str;
{
	register int num;

	num = 0;
	while ('0' <= *str && *str <= '7') {
		num *= 8;
		num += (*str++) - '0';
	}
	return(num);
}

/*
 *      Umwandlung eines ASCII-Strings mit einer Binaerzahl in
 *      einen Integer.
 *      Format: nnnnnnnnnnnnnnnnB
 */
abtoi(str)
register char *str;
{
	register int num;

	num = 0;
	while ('0' <= *str && *str <= '1') {
		num *= 2;
		num += (*str++) - '0';
	}
	return(num);
}

/*
 *      Umwandlung eines ASCII-Strings in einen Integer.
 */
strval(str)
register char *str;
{
	register int num;

	num = 0;
	while (*str) {
		num <<= 8;
		num += (int) *str++;
	}
	return(num);
}

/*
 *      Die Funktion prueft einen Wert auf -256 < Wert < 256
 *      Output: Wert wenn im Bereich, sonst 0 und Fehlermeldung
 */
chk_v1(i)
register int i;
{
	if (i >= -255 && i <= 255)
		return(i);
	else {
		asmerr(E_VALOUT);
		return(0);
	}
}

/*
 *      Die Funktion prueft einen Wert auf -128 < Wert < 128
 *      Output: Wert wenn im Bereich, sonst 0 und Fehlermeldung
 */
chk_v2(i)
register int i;
{
	if (i >= -127 && i <= 127)
		return(i);
	else {
		asmerr(E_VALOUT);
		return(0);
	}
}
