/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *      Dieses Modul enthaelt die Funktionen zur Bearbeitung
 *      aller Op-Codes
 */

#include <stdio.h>
#include "z80a.h"
#include "z80aglb.h"

/*
 *      Diese Funktion behandelt alle Op-Codes,
 *      die keine Argumente benoetigen, und
 *      ein Byte Op-Code Laenge haben
 */
op_1b(b1, dummy)
int b1, dummy;
{
	if (pass == 1) {                /* Pass 1 */
		if (*label)
			put_label();
	} else                          /* Pass 2 */
		ops[0] = b1;
	return(1);
}

/*
 *      Diese Funktion behandelt alle Op-Codes,
 *      die keine Argumente benoetigen, und
 *      zwei Byte Op-Code Laenge haben
 */
op_2b(b1, b2)
int b1, b2;
{
	if (pass == 1) {                /* Pass 1 */
		if (*label)
			put_label();
	} else {                        /* Pass 2 */
		ops[0] = b1;
		ops[1] = b2;
	}
	return(2);
}

/*
 *      Diese Funktion behandelt die Op-Codes IM
 */
op_im()
{
	if (pass == 1)
		if (*label)
			put_label();
	if (pass == 2) {
		ops[0] = 0xed;
		switch(eval(operand)) {
		case 0:
			ops[1] = 0x46;
			break;
		case 1:
			ops[1] = 0x56;
			break;
		case 2:
			ops[1] = 0x5e;
			break;
		default:
			ops[1] = 0;
			asmerr(E_ILLOPE);
			break;
		}
	}
	return(2);
}

/*
 *      Diese Funktion behandelt die Op-Codes PUSH und POP
 */
op_pupo(op_code, dummy)
int op_code, dummy;
{
	register int len;

	if (pass == 1)
		if (*label)
			put_label();
	switch (get_reg(operand)) {
	case REGAF:
		if (pass == 2) {
			if (op_code == 1)
				ops[0] = 0xf1;     /* POP AF */
			else
				ops[0] = 0xf5;     /* PUSH AF */
		}
		len = 1;
		break;
	case REGBC:
		if (pass == 2) {
			if (op_code == 1)
				ops[0] = 0xc1;     /* POP BC */
			else
				ops[0] = 0xc5;     /* PUSH BC */
		}
		len = 1;
		break;
	case REGDE:
		if (pass == 2) {
			if (op_code == 1)
				ops[0] = 0xd1;     /* POP DE */
			else
				ops[0] = 0xd5;     /* PUSH DE */
		}
		len = 1;
		break;
	case REGHL:
		if (pass == 2) {
			if (op_code == 1)
				ops[0] = 0xe1;     /* POP HL */
			else
				ops[0] = 0xe5;     /* PUSH HL */
		}
		len = 1;
		break;
	case REGIX:
		if (pass == 2) {
			if (op_code == 1) {
				ops[0] = 0xdd;     /* POP IX */
				ops[1] = 0xe1;
			} else {
				ops[0] = 0xdd;     /* PUSH IX */
				ops[1] = 0xe5;
			}
		}
		len = 2;
		break;
	case REGIY:
		if (pass == 2) {
			if (op_code == 1) {
				ops[0] = 0xfd;     /* POP IY */
				ops[1] = 0xe1;
			} else {
				ops[0] = 0xfd;     /* PUSH IY */
				ops[1] = 0xe5;
			}
		}
		len = 2;
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Diese Funktion behandelt den EX Op-Code
 */
op_ex()
{
	register int len;

	if (pass == 1)
		if (*label)
			put_label();
	if (strncmp(operand, "DE,HL", 5) == 0) {
		ops[0] = 0xeb;
		len = 1;
	} else if (strncmp(operand, "AF,AF'", 7) == 0) {
		ops[0] = 0x08;
		len = 1;
	} else if (strncmp(operand, "(SP),HL", 7) == 0) {
		ops[0] = 0xe3;
		len = 1;
	} else if (strncmp(operand, "(SP),IX", 7) == 0) {
		ops[0] = 0xdd;
		ops[1] = 0xe3;
		len = 2;
	} else if (strncmp(operand, "(SP),IY", 7) == 0) {
		ops[0] = 0xfd;
		ops[1] = 0xe3;
		len = 2;
	} else {
		ops[0] = 0;
		len = 1;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Diese Funktion behandelt den CALL Op-Code
 */
op_call()
{
	char *strchr();
	register char *p1, *p2;
	register int i;

	if (pass == 1) {        /* PASS 1 */
		if (*label)
			put_label();
	} else {                /* PASS 2 */
		p1 = operand;
		p2 = tmp;
		while (*p1 != ',' && *p1 != '\0')
			*p2++ = *p1++;
		*p2 = '\0';
		switch (get_reg(tmp)) {
		case REGC:                      /* CALL C,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xdc;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGNC:                     /* CALL NC,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xd4;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGZ:                      /* CALL Z,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xcc;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGNZ:                     /* CALL NZ,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xc4;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGPE:                     /* CALL PE,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xec;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGPO:                     /* CALL PO,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xe4;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGM:                      /* CALL M,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xfc;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case FLGP:                      /* CALL P,nn */
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xf4;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case NOREG:                     /* CALL nn */
			i = eval(operand);
			ops[0] = 0xcd;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
			break;
		case NOOPERA:                   /* Operand fehlt */
			ops[0] = 0;
			ops[1] = 0;
			ops[2] = 0;
			asmerr(E_MISOPE);
			break;
		default:                        /* ungueltiger Operand */
			ops[0] = 0;
			ops[1] = 0;
			ops[2] = 0;
			asmerr(E_ILLOPE);
		}
	}
	return(3);
}

/*
 *      Diese Funktion behandelt den RST Op-Code
 */
op_rst()
{
	register int op;

	if (pass == 1) {        /* PASS 1 */
		if (*label)
			put_label();
	} else {                /* PASS 2 */
		op = eval(operand);
		if ((op / 8 > 7) || (op % 8 != 0)) {
			ops[0] = 0;
			asmerr(E_VALOUT);
		} else
			ops[0] = 0xc7 + op;
	}
	return(1);
}

/*
 *      Diese Funktion behandelt den RET Op-Code
 */
op_ret()
{
	if (pass == 1) {        /* PASS 1 */
		if (*label)
			put_label();
	} else {                /* PASS 2 */
		switch (get_reg(operand)) {
		case NOOPERA:                   /* RET */
			ops[0] = 0xc9;
			break;
		case REGC:                      /* RET C */
			ops[0] = 0xd8;
			break;
		case FLGNC:                     /* RET NC */
			ops[0] = 0xd0;
			break;
		case FLGZ:                      /* RET Z */
			ops[0] = 0xc8;
			break;
		case FLGNZ:                     /* RET NZ */
			ops[0] = 0xc0;
			break;
		case FLGPE:                     /* RET PE */
			ops[0] = 0xe8;
			break;
		case FLGPO:                     /* RET PO */
			ops[0] = 0xe0;
			break;
		case FLGM:                      /* RET M */
			ops[0] = 0xf8;
			break;
		case FLGP:                      /* RET P */
			ops[0] = 0xf0;
			break;
		default:                        /* ungueltiger Operand */
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
	}
	return(1);
}

/*
 *      Diese Funktion behandelt den JP Op-Code
 */
op_jp()
{
	char *strchr();
	register char *p1, *p2;
	register int i, len;

	if (pass == 1)
		if (*label)
			put_label();
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	switch (get_reg(tmp)) {
	case REGC:                      /* JP C,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xda;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGNC:                     /* JP NC,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xd2;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGZ:                      /* JP Z,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xca;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGNZ:                     /* JP NZ,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xc2;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGPE:                     /* JP PE,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xea;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGPO:                     /* JP PO,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xe2;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGM:                      /* JP M,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xfa;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case FLGP:                      /* JP P,nn */
		len = 3;
		if (pass == 2) {
			i = eval(strchr(operand, ',') + 1);
			ops[0] = 0xf2;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case REGIHL:                    /* JP (HL) */
		ops[0] = 0xe9;
		len = 1;
		break;
	case REGIIX:                    /* JP (IX) */
		ops[0] = 0xdd;
		ops[1] = 0xe9;
		len = 2;
		break;
	case REGIIY:                    /* JP (IY) */
		ops[0] = 0xfd;
		ops[1] = 0xe9;
		len = 2;
		break;
	case NOREG:                     /* JP nn */
		len = 3;
		if (pass == 2) {
			i = eval(operand);
			ops[0] = 0xc3;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		len = 1;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		len = 1;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Diese Funktion behandelt den JR Op-Code
 */
op_jr()
{
	char *strchr();
	register char *p1, *p2;

	if (pass == 1) {        /* PASS 1 */
		if (*label)
			put_label();
	} else {                /* PASS 2 */
		p1 = operand;
		p2 = tmp;
		while (*p1 != ',' && *p1 != '\0')
			*p2++ = *p1++;
		*p2 = '\0';
		switch (get_reg(tmp)) {
		case REGC:                      /* JR C,n */
			ops[0] = 0x38;
			ops[1] = chk_v2(eval(strchr(operand, ',') + 1) - pc - 2);
			break;
		case FLGNC:                     /* JR NC,n */
			ops[0] = 0x30;
			ops[1] = chk_v2(eval(strchr(operand, ',') + 1) - pc - 2);
			break;
		case FLGZ:                      /* JR Z,n */
			ops[0] = 0x28;
			ops[1] = chk_v2(eval(strchr(operand, ',') + 1) - pc - 2);
			break;
		case FLGNZ:                     /* JR NZ,n */
			ops[0] = 0x20;
			ops[1] = chk_v2(eval(strchr(operand, ',') + 1) - pc - 2);
			break;
		case NOREG:                     /* JR n */
			ops[0] = 0x18;
			ops[1] = chk_v2(eval(operand) - pc - 2);
			break;
		case NOOPERA:                   /* Operand fehlt */
			ops[0] = 0;
			ops[1] = 0;
			asmerr(E_MISOPE);
			break;
		default:                        /* ungueltiger Operand */
			ops[0] = 0;
			ops[1] = 0;
			asmerr(E_ILLOPE);
		}
	}
	return(2);
}

/*
 *      Diese Funktion behandelt den DJNZ Op-Code
 */
op_djnz()
{
	if (pass == 1) {        /* PASS 1 */
		if (*label)
			put_label();
	} else {                /* PASS 2 */
		ops[0] = 0x10;
		ops[1] = chk_v2(eval(operand) - pc - 2);
	}
	return(2);
}

/*
 *      Diese Funktion behandelt die LD Op-Codes
 */
op_ld()
{
	register int len;
	register char *p1, *p2;
	char *get_second();

	if (pass == 1)
		if (*label)
			put_label();
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	switch (get_reg(tmp)) {
	case REGA:                      /* LD A,? */
		len = lda();
		break;
	case REGB:                      /* LD B,? */
		len = ldb();
		break;
	case REGC:                      /* LD C,? */
		len = ldc();
		break;
	case REGD:                      /* LD D,? */
		len = ldd();
		break;
	case REGE:                      /* LD E,? */
		len = lde();
		break;
	case REGH:                      /* LD H,? */
		len = ldh();
		break;
	case REGL:                      /* LD L,? */
		len = ldl();
		break;
	case REGI:                      /* LD I,A */
		if (get_reg(get_second(operand)) == REGA) {
			len = 2;
			ops[0] = 0xed;
			ops[1] = 0x47;
			break;
		}
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
		break;
	case REGR:                      /* LD R,A */
		if (get_reg(get_second(operand)) == REGA) {
			len = 2;
			ops[0] = 0xed;
			ops[1] = 0x4f;
			break;
		}
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
		break;
	case REGBC:                     /* LD BC,? */
		len = ldbc();
		break;
	case REGDE:                     /* LD DE,? */
		len = ldde();
		break;
	case REGHL:                     /* LD HL,? */
		len = ldhl();
		break;
	case REGIX:                     /* LD IX,? */
		len = ldix();
		break;
	case REGIY:                     /* LD IY,? */
		len = ldiy();
		break;
	case REGSP:                     /* LD SP,? */
		len = ldsp();
		break;
	case REGIHL:                    /* LD (HL),? */
		len = ldihl();
		break;
	case REGIBC:                    /* LD (BC),A */
		if (get_reg(get_second(operand)) == REGA) {
			len = 1;
			ops[0] = 0x02;
			break;
		}
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
		break;
	case REGIDE:                    /* LD (DE),A */
		if (get_reg(get_second(operand)) == REGA) {
			len = 1;
			ops[0] = 0x12;
			break;
		}
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		if (strncmp(operand, "(IX+", 4) == 0)
			len = ldiix();  /* LD (IX+d),? */
		else if (strncmp(operand, "(IY+", 4) == 0)
			len = ldiiy();  /* LD (IY+d),? */
		else if (*operand == '(')
			len = ldinn();  /* LD (nn),? */
		else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD A,?
 */
lda()
{
	char *get_second(), *strchr();
	register int op;
	register int i, len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD A,A */
	case REGB:                      /* LD A,B */
	case REGC:                      /* LD A,C */
	case REGD:                      /* LD A,D */
	case REGE:                      /* LD A,E */
	case REGH:                      /* LD A,H */
	case REGL:                      /* LD A,L */
	case REGIHL:                    /* LD A,(HL) */
		len = 1;
		ops[0] = 0x78 + op;
		break;
	case REGI:                      /* LD A,I */
		len = 2;
		ops[0] = 0xed;
		ops[1] = 0x57;
		break;
	case REGR:                      /* LD A,R */
		len = 2;
		ops[0] = 0xed;
		ops[1] = 0x5f;
		break;
	case REGIBC:                    /* LD A,(BC) */
		len = 1;
		ops[0] = 0x0a;
		break;
	case REGIDE:                    /* LD A,(DE) */
		len = 1;
		ops[0] = 0x1a;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD A,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x7e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD A,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x7e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 3;                /* LD A,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0x3a;
				ops[1] = i & 255;
				ops[2] = i >> 8;
			}
			break;
		}
		len = 2;                        /* LD A,n */
		if (pass == 2) {
			ops[0] = 0x3e;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD B,?
 */
ldb()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD B,A */
	case REGB:                      /* LD B,B */
	case REGC:                      /* LD B,C */
	case REGD:                      /* LD B,D */
	case REGE:                      /* LD B,E */
	case REGH:                      /* LD B,H */
	case REGL:                      /* LD B,L */
	case REGIHL:                    /* LD B,(HL) */
		len = 1;
		ops[0] = 0x40 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD B,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x46;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD B,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x46;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD B,n */
		if (pass == 2) {
			ops[0] = 0x06;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD C,?
 */
ldc()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD C,A */
	case REGB:                      /* LD C,B */
	case REGC:                      /* LD C,C */
	case REGD:                      /* LD C,D */
	case REGE:                      /* LD C,E */
	case REGH:                      /* LD C,H */
	case REGL:                      /* LD C,L */
	case REGIHL:                    /* LD C,(HL) */
		len = 1;
		ops[0] = 0x48 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD C,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x4e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD C,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x4e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD C,n */
		if (pass == 2) {
			ops[0] = 0x0e;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD D,?
 */
ldd()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD D,A */
	case REGB:                      /* LD D,B */
	case REGC:                      /* LD D,C */
	case REGD:                      /* LD D,D */
	case REGE:                      /* LD D,E */
	case REGH:                      /* LD D,H */
	case REGL:                      /* LD D,L */
	case REGIHL:                    /* LD D,(HL) */
		len = 1;
		ops[0] = 0x50 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD D,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x56;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD D,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x56;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD D,n */
		if (pass == 2) {
			ops[0] = 0x16;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD E,?
 */
lde()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD E,A */
	case REGB:                      /* LD E,B */
	case REGC:                      /* LD E,C */
	case REGD:                      /* LD E,D */
	case REGE:                      /* LD E,E */
	case REGH:                      /* LD E,H */
	case REGL:                      /* LD E,L */
	case REGIHL:                    /* LD E,(HL) */
		len = 1;
		ops[0] = 0x58 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD E,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x5e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD E,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x5e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD E,n */
		if (pass == 2) {
			ops[0] = 0x1e;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD H,?
 */
ldh()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD H,A */
	case REGB:                      /* LD H,B */
	case REGC:                      /* LD H,C */
	case REGD:                      /* LD H,D */
	case REGE:                      /* LD H,E */
	case REGH:                      /* LD H,H */
	case REGL:                      /* LD H,L */
	case REGIHL:                    /* LD H,(HL) */
		len = 1;
		ops[0] = 0x60 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD H,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x66;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD H,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x66;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD H,n */
		if (pass == 2) {
			ops[0] = 0x26;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD L,?
 */
ldl()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD L,A */
	case REGB:                      /* LD L,B */
	case REGC:                      /* LD L,C */
	case REGD:                      /* LD L,D */
	case REGE:                      /* LD L,E */
	case REGH:                      /* LD L,H */
	case REGL:                      /* LD L,L */
	case REGIHL:                    /* LD L,(HL) */
		len = 1;
		ops[0] = 0x68 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) { /* LD L,(IX+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x6e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		if (strncmp(p, "(IY+", 4) == 0) { /* LD L,(IY+d) */
			len = 3;
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x6e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
			break;
		}
		len = 2;                        /* LD L,n */
		if (pass == 2) {
			ops[0] = 0x2e;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD BC,?
 */
ldbc()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 4;                /* LD BC,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0xed;
				ops[1] = 0x4b;
				ops[2] = i & 0xff;
				ops[3] = i >> 8;
			}
			break;
		}
		len = 3;                        /* LD BC,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0x01;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD DE,?
 */
ldde()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 4;                /* LD DE,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0xed;
				ops[1] = 0x5b;
				ops[2] = i & 0xff;
				ops[3] = i >> 8;
			}
			break;
		}
		len = 3;                        /* LD DE,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0x11;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD HL,?
 */
ldhl()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 3;                /* LD HL,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0x2a;
				ops[1] = i & 0xff;
				ops[2] = i >> 8;
			}
			break;
		}
		len = 3;                        /* LD HL,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0x21;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD IX,?
 */
ldix()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 4;                /* LD IX,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0xdd;
				ops[1] = 0x2a;
				ops[2] = i & 0xff;
				ops[3] = i >> 8;
			}
			break;
		}
		len = 4;                        /* LD IX,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0xdd;
			ops[1] = 0x21;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD IY,?
 */
ldiy()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 4;                /* LD IY,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0xfd;
				ops[1] = 0x2a;
				ops[2] = i & 0xff;
				ops[3] = i >> 8;
			}
			break;
		}
		len = 4;                        /* LD IY,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0xfd;
			ops[1] = 0x21;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD SP,?
 */
ldsp()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case REGHL:                     /* LD SP,HL */
		len = 1;
		ops[0] = 0xf9;
		break;
	case REGIX:                     /* LD SP,IX */
		len = 2;
		ops[0] = 0xdd;
		ops[1] = 0xf9;
		break;
	case REGIY:                     /* LD SP,IY */
		len = 2;
		ops[0] = 0xfd;
		ops[1] = 0xf9;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (*p == '(' && *(p + strlen(p) - 1) == ')') {
			len = 4;                /* LD SP,(nn) */
			if (pass == 2) {
				i = calc_val(p + 1);
				ops[0] = 0xed;
				ops[1] = 0x7b;
				ops[2] = i & 0xff;
				ops[3] = i >> 8;
			}
			break;
		}
		len = 3;                        /* LD SP,nn */
		if (pass == 2) {
			i = eval(p);
			ops[0] = 0x31;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD (HL),?
 */
ldihl()
{
	register int op;
	register int len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD (HL),A */
	case REGB:                      /* LD (HL),B */
	case REGC:                      /* LD (HL),C */
	case REGD:                      /* LD (HL),D */
	case REGE:                      /* LD (HL),E */
	case REGH:                      /* LD (HL),H */
	case REGL:                      /* LD (HL),L */
		len = 1;
		ops[0] = 0x70 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		len = 2;                /* LD (HL),n */
		if (pass == 2) {
			ops[0] = 0x36;
			ops[1] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD (IX+d),?
 */
ldiix()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD (IX+d),A */
	case REGB:                      /* LD (IX+d),B */
	case REGC:                      /* LD (IX+d),C */
	case REGD:                      /* LD (IX+d),D */
	case REGE:                      /* LD (IX+d),E */
	case REGH:                      /* LD (IX+d),H */
	case REGL:                      /* LD (IX+d),L */
		len = 3;
		if (pass == 2) {
			ops[0] = 0xdd;
			ops[1] = 0x70 + op;
			ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
		}
		break;
	case NOREG:                     /* LD (IX+d),n */
		len = 4;
		if (pass == 2) {
			ops[0] = 0xdd;
			ops[1] = 0x36;
			ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			ops[3] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD (IY+d),?
 */
ldiiy()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* LD (IY+d),A */
	case REGB:                      /* LD (IY+d),B */
	case REGC:                      /* LD (IY+d),C */
	case REGD:                      /* LD (IY+d),D */
	case REGE:                      /* LD (IY+d),E */
	case REGH:                      /* LD (IY+d),H */
	case REGL:                      /* LD (IY+d),L */
		len = 3;
		if (pass == 2) {
			ops[0] = 0xfd;
			ops[1] = 0x70 + op;
			ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
		}
		break;
	case NOREG:                     /* LD (IY+d),n */
		len = 4;
		if (pass == 2) {
			ops[0] = 0xfd;
			ops[1] = 0x36;
			ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			ops[3] = chk_v1(eval(p));
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes LD (nn),?
 */
ldinn()
{
	register int i, len;
	register char *p;
	char *get_second();

	p = get_second(operand);
	switch (get_reg(p)) {
	case REGA:                      /* LD (nn),A */
		len = 3;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0x32;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case REGBC:                     /* LD (nn),BC */
		len = 4;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0xed;
			ops[1] = 0x43;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case REGDE:                     /* LD (nn),DE */
		len = 4;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0xed;
			ops[1] = 0x53;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case REGHL:                     /* LD (nn),HL */
		len = 3;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0x22;
			ops[1] = i & 0xff;
			ops[2] = i >> 8;
		}
		break;
	case REGSP:                     /* LD (nn),SP */
		len = 4;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0xed;
			ops[1] = 0x73;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case REGIX:                     /* LD (nn),IX */
		len = 4;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0xdd;
			ops[1] = 0x22;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case REGIY:                     /* LD (nn),IY */
		len = 4;
		if (pass == 2) {
			i = calc_val(operand + 1);
			ops[0] = 0xfd;
			ops[1] = 0x22;
			ops[2] = i & 0xff;
			ops[3] = i >> 8;
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADD ?,?
 */
op_add()
{
	register int len;
	register char *p1, *p2;

	if (pass == 1)
		if (*label)
			put_label();
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	switch (get_reg(tmp)) {
	case REGA:                      /* ADD A,? */
		len = adda();
		break;
	case REGHL:                     /* ADD HL,? */
		len = addhl();
		break;
	case REGIX:                     /* ADD IX,? */
		len = addix();
		break;
	case REGIY:                     /* ADD IY,? */
		len = addiy();
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADD A,?
 */
adda()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* ADD A,A */
	case REGB:                      /* ADD A,B */
	case REGC:                      /* ADD A,C */
	case REGD:                      /* ADD A,D */
	case REGE:                      /* ADD A,E */
	case REGH:                      /* ADD A,H */
	case REGL:                      /* ADD A,L */
	case REGIHL:                    /* ADD A,(HL) */
		len = 1;
		ops[0] = 0x80 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) {
			len = 3;        /* ADD A,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x86;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else if (strncmp(p, "(IY+", 4) == 0) {
			len = 3;        /* ADD A,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x86;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else {
			len = 2;        /* ADD A,n */
			if (pass == 2) {
				ops[0] = 0xc6;
				ops[1] = chk_v1(eval(p));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADD HL,?
 */
addhl()
{
	char *get_second();

	switch (get_reg(get_second(operand))) {
	case REGBC:                     /* ADD HL,BC */
		ops[0] = 0x09;
		break;
	case REGDE:                     /* ADD HL,DE */
		ops[0] = 0x19;
		break;
	case REGHL:                     /* ADD HL,HL */
		ops[0] = 0x29;
		break;
	case REGSP:                     /* ADD HL,SP */
		ops[0] = 0x39;
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(1);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADD IX,?
 */
addix()
{
	char *get_second();

	switch (get_reg(get_second(operand))) {
	case REGBC:                     /* ADD IX,BC */
		ops[0] = 0xdd;
		ops[1] = 0x09;
		break;
	case REGDE:                     /* ADD IX,DE */
		ops[0] = 0xdd;
		ops[1] = 0x19;
		break;
	case REGIX:                     /* ADD IX,IX */
		ops[0] = 0xdd;
		ops[1] = 0x29;
		break;
	case REGSP:                     /* ADD IX,SP */
		ops[0] = 0xdd;
		ops[1] = 0x39;
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(2);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADD IY,?
 */
addiy()
{
	char *get_second();

	switch (get_reg(get_second(operand))) {
	case REGBC:                     /* ADD IY,BC */
		ops[0] = 0xfd;
		ops[1] = 0x09;
		break;
	case REGDE:                     /* ADD IY,DE */
		ops[0] = 0xfd;
		ops[1] = 0x19;
		break;
	case REGIY:                     /* ADD IY,IY */
		ops[0] = 0xfd;
		ops[1] = 0x29;
		break;
	case REGSP:                     /* ADD IY,SP */
		ops[0] = 0xfd;
		ops[1] = 0x39;
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(2);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADC ?,?
 */
op_adc()
{
	register int len;
	register char *p1, *p2;

	if (pass == 1)
		if (*label)
			put_label();
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	switch (get_reg(tmp)) {
	case REGA:                      /* ADC A,? */
		len = adca();
		break;
	case REGHL:                     /* ADC HL,? */
		len = adchl();
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADC A,?
 */
adca()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* ADC A,A */
	case REGB:                      /* ADC A,B */
	case REGC:                      /* ADC A,C */
	case REGD:                      /* ADC A,D */
	case REGE:                      /* ADC A,E */
	case REGH:                      /* ADC A,H */
	case REGL:                      /* ADC A,L */
	case REGIHL:                    /* ADC A,(HL) */
		len = 1;
		ops[0] = 0x88 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) {
			len = 3;        /* ADC A,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x8e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else if (strncmp(p, "(IY+", 4) == 0) {
			len = 3;        /* ADC A,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x8e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else {
			len = 2;        /* ADD A,n */
			if (pass == 2) {
				ops[0] = 0xce;
				ops[1] = chk_v1(eval(p));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes ADC HL,?
 */
adchl()
{
	char *get_second();

	switch (get_reg(get_second(operand))) {
	case REGBC:                     /* ADC HL,BC */
		ops[0] = 0xed;
		ops[1] = 0x4a;
		break;
	case REGDE:                     /* ADC HL,DE */
		ops[0] = 0xed;
		ops[1] = 0x5a;
		break;
	case REGHL:                     /* ADC HL,HL */
		ops[0] = 0xed;
		ops[1] = 0x6a;
		break;
	case REGSP:                     /* ADC HL,SP */
		ops[0] = 0xed;
		ops[1] = 0x7a;
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(2);
}

/*
 *      Die Funktion behandelt alle Op-Codes SUB ?
 */
op_sub()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* SUB A */
	case REGB:                      /* SUB B */
	case REGC:                      /* SUB C */
	case REGD:                      /* SUB D */
	case REGE:                      /* SUB E */
	case REGH:                      /* SUB H */
	case REGL:                      /* SUB L */
	case REGIHL:                    /* SUB (HL) */
		len = 1;
		ops[0] = 0x90 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* SUB (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x96;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* SUB (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x96;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 2;        /* SUB n */
			if (pass == 2) {
				ops[0] = 0xd6;
				ops[1] = chk_v1(eval(operand));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes SBC ?,?
 */
op_sbc()
{
	register int len;
	register char *p1, *p2;

	if (pass == 1)
		if (*label)
			put_label();
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	switch (get_reg(tmp)) {
	case REGA:                      /* SBC A,? */
		len = sbca();
		break;
	case REGHL:                     /* SBC HL,? */
		len = sbchl();
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes SBC A,?
 */
sbca()
{
	char *get_second(), *strchr();
	register int op;
	register int len;
	register char *p;

	p = get_second(operand);
	switch (op = get_reg(p)) {
	case REGA:                      /* SBC A,A */
	case REGB:                      /* SBC A,B */
	case REGC:                      /* SBC A,C */
	case REGD:                      /* SBC A,D */
	case REGE:                      /* SBC A,E */
	case REGH:                      /* SBC A,H */
	case REGL:                      /* SBC A,L */
	case REGIHL:                    /* SBC A,(HL) */
		len = 1;
		ops[0] = 0x98 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p, "(IX+", 4) == 0) {
			len = 3;        /* SBC A,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x9e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else if (strncmp(p, "(IY+", 4) == 0) {
			len = 3;        /* SBC A,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x9e;
				ops[2] = chk_v2(calc_val(strchr(p, '+') + 1));
			}
		} else {
			len = 2;        /* SBC A,n */
			if (pass == 2) {
				ops[0] = 0xde;
				ops[1] = chk_v1(eval(p));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes SBC HL,?
 */
sbchl()
{
	char *get_second();

	switch (get_reg(get_second(operand))) {
	case REGBC:                     /* SBC HL,BC */
		ops[0] = 0xed;
		ops[1] = 0x42;
		break;
	case REGDE:                     /* SBC HL,DE */
		ops[0] = 0xed;
		ops[1] = 0x52;
		break;
	case REGHL:                     /* SBC HL,HL */
		ops[0] = 0xed;
		ops[1] = 0x62;
		break;
	case REGSP:                     /* SBC HL,SP */
		ops[0] = 0xed;
		ops[1] = 0x72;
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[0] = 0;
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(2);
}

/*
 *      Die Funktion behandelt alle Op-Codes INC ?
 */
op_inc()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* INC A */
	case REGB:                      /* INC B */
	case REGC:                      /* INC C */
	case REGD:                      /* INC D */
	case REGE:                      /* INC E */
	case REGH:                      /* INC H */
	case REGL:                      /* INC L */
	case REGIHL:                    /* INC (HL) */
		len = 1;
		ops[0] = 0x04 + (op << 3);
		break;
	case REGBC:                     /* INC BC */
		len = 1;
		ops[0] = 0x03;
		break;
	case REGDE:                     /* INC DE */
		len = 1;
		ops[0] = 0x13;
		break;
	case REGHL:                     /* INC HL */
		len = 1;
		ops[0] = 0x23;
		break;
	case REGSP:                     /* INC SP */
		len = 1;
		ops[0] = 0x33;
		break;
	case REGIX:                     /* INC IX */
		len = 2;
		ops[0] = 0xdd;
		ops[1] = 0x23;
		break;
	case REGIY:                     /* INC IY */
		len = 2;
		ops[0] = 0xfd;
		ops[1] = 0x23;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* INC (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x34;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* INC (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x34;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes DEC ?
 */
op_dec()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* DEC A */
	case REGB:                      /* DEC B */
	case REGC:                      /* DEC C */
	case REGD:                      /* DEC D */
	case REGE:                      /* DEC E */
	case REGH:                      /* DEC H */
	case REGL:                      /* DEC L */
	case REGIHL:                    /* DEC (HL) */
		len = 1;
		ops[0] = 0x05 + (op << 3);
		break;
	case REGBC:                     /* DEC BC */
		len = 1;
		ops[0] = 0x0b;
		break;
	case REGDE:                     /* DEC DE */
		len = 1;
		ops[0] = 0x1b;
		break;
	case REGHL:                     /* DEC HL */
		len = 1;
		ops[0] = 0x2b;
		break;
	case REGSP:                     /* DEC SP */
		len = 1;
		ops[0] = 0x3b;
		break;
	case REGIX:                     /* DEC IX */
		len = 2;
		ops[0] = 0xdd;
		ops[1] = 0x2b;
		break;
	case REGIY:                     /* DEC IY */
		len = 2;
		ops[0] = 0xfd;
		ops[1] = 0x2b;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* DEC (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0x35;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* DEC (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0x35;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes OR ?
 */
op_or()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* OR A */
	case REGB:                      /* OR B */
	case REGC:                      /* OR C */
	case REGD:                      /* OR D */
	case REGE:                      /* OR E */
	case REGH:                      /* OR H */
	case REGL:                      /* OR L */
	case REGIHL:                    /* OR (HL) */
		len = 1;
		ops[0] = 0xb0 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* OR (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xb6;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* OR (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xb6;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 2;        /* OR n */
			if (pass == 2) {
				ops[0] = 0xf6;
				ops[1] = chk_v1(eval(operand));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes XOR ?
 */
op_xor()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* XOR A */
	case REGB:                      /* XOR B */
	case REGC:                      /* XOR C */
	case REGD:                      /* XOR D */
	case REGE:                      /* XOR E */
	case REGH:                      /* XOR H */
	case REGL:                      /* XOR L */
	case REGIHL:                    /* XOR (HL) */
		len = 1;
		ops[0] = 0xa8 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* XOR (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xae;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* XOR (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xae;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 2;        /* XOR n */
			if (pass == 2) {
				ops[0] = 0xee;
				ops[1] = chk_v1(eval(operand));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes AND ?
 */
op_and()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* AND A */
	case REGB:                      /* AND B */
	case REGC:                      /* AND C */
	case REGD:                      /* AND D */
	case REGE:                      /* AND E */
	case REGH:                      /* AND H */
	case REGL:                      /* AND L */
	case REGIHL:                    /* AND (HL) */
		len = 1;
		ops[0] = 0xa0 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* AND (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xa6;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* AND (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xa6;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 2;        /* AND n */
			if (pass == 2) {
				ops[0] = 0xe6;
				ops[1] = chk_v1(eval(operand));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt alle Op-Codes CP ?
 */
op_cp()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* CP A */
	case REGB:                      /* CP B */
	case REGC:                      /* CP C */
	case REGD:                      /* CP D */
	case REGE:                      /* CP E */
	case REGH:                      /* CP H */
	case REGL:                      /* CP L */
	case REGIHL:                    /* CP (HL) */
		len = 1;
		ops[0] = 0xb8 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 3;        /* CP (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xbe;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 3;        /* CP (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xbe;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
			}
		} else {
			len = 2;        /* OR n */
			if (pass == 2) {
				ops[0] = 0xfe;
				ops[1] = chk_v1(eval(operand));
			}
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den RL Op-Code
 */
op_rl()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* RL A */
	case REGB:                      /* RL B */
	case REGC:                      /* RL C */
	case REGD:                      /* RL D */
	case REGE:                      /* RL E */
	case REGH:                      /* RL H */
	case REGL:                      /* RL L */
	case REGIHL:                    /* RL (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x10 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* RL (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x16;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* RL (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x16;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den RR Op-Code
 */
op_rr()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* RR A */
	case REGB:                      /* RR B */
	case REGC:                      /* RR C */
	case REGD:                      /* RR D */
	case REGE:                      /* RR E */
	case REGH:                      /* RR H */
	case REGL:                      /* RR L */
	case REGIHL:                    /* RR (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x18 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* RR (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x1e;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* RR (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x1e;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den SLA Op-Code
 */
op_sla()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* SLA A */
	case REGB:                      /* SLA B */
	case REGC:                      /* SLA C */
	case REGD:                      /* SLA D */
	case REGE:                      /* SLA E */
	case REGH:                      /* SLA H */
	case REGL:                      /* SLA L */
	case REGIHL:                    /* SLA (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x20 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* SLA (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x26;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* SLA (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x26;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den SRA Op-Code
 */
op_sra()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* SRA A */
	case REGB:                      /* SRA B */
	case REGC:                      /* SRA C */
	case REGD:                      /* SRA D */
	case REGE:                      /* SRA E */
	case REGH:                      /* SRA H */
	case REGL:                      /* SRA L */
	case REGIHL:                    /* SRA (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x28 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* SRA (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x2e;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* SRA (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x2e;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den SRL Op-Code
 */
op_srl()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* SRL A */
	case REGB:                      /* SRL B */
	case REGC:                      /* SRL C */
	case REGD:                      /* SRL D */
	case REGE:                      /* SRL E */
	case REGH:                      /* SRL H */
	case REGL:                      /* SRL L */
	case REGIHL:                    /* SRL (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x38 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* SRL (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x3e;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* SRL (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x3e;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den RLC Op-Code
 */
op_rlc()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* RLC A */
	case REGB:                      /* RLC B */
	case REGC:                      /* RLC C */
	case REGD:                      /* RLC D */
	case REGE:                      /* RLC E */
	case REGH:                      /* RLC H */
	case REGL:                      /* RLC L */
	case REGIHL:                    /* RLC (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x00 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* RLC (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x06;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* RLC (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x06;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den RRC Op-Code
 */
op_rrc()
{
	char *strchr();
	register int len, op;

	if (pass == 1)
		if (*label)
			put_label();
	switch (op = get_reg(operand)) {
	case REGA:                      /* RRC A */
	case REGB:                      /* RRC B */
	case REGC:                      /* RRC C */
	case REGD:                      /* RRC D */
	case REGE:                      /* RRC E */
	case REGH:                      /* RRC H */
	case REGL:                      /* RRC L */
	case REGIHL:                    /* RRC (HL) */
		len = 2;
		ops[0] = 0xcb;
		ops[1] = 0x08 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(operand, "(IX+", 4) == 0) {
			len = 4;        /* RRC (IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x0e;
			}
		} else if (strncmp(operand, "(IY+", 4) == 0) {
			len = 4;        /* RRC (IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x0e;
			}
		} else {
			len = 1;
			ops[0] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		len = 1;
		ops[0] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		len = 1;
		ops[0] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion behandelt den OUT Op-Code
 */
op_out()
{
	register int op;
	char *get_second();

	if (pass == 1) {                /* PASS 1 */
		if (*label)
			put_label();
	} else {                        /* PASS 2 */
		if (strncmp(operand, "(C),", 4) == 0) {
			switch(op = get_reg(get_second(operand))) {
			case REGA:      /* OUT (C),A */
			case REGB:      /* OUT (C),B */
			case REGC:      /* OUT (C),C */
			case REGD:      /* OUT (C),D */
			case REGE:      /* OUT (C),E */
			case REGH:      /* OUT (C),H */
			case REGL:      /* OUT (C),L */
				ops[0] = 0xed;
				ops[1] = 0x41 + (op << 3);
				break;
			case NOOPERA:   /* Operand fehlt */
				ops[0] = 0;
				ops[1] = 0;
				asmerr(E_MISOPE);
				break;
			default:        /* ungueltiger Operand */
				ops[0] = 0;
				ops[1] = 0;
				asmerr(E_ILLOPE);
			}
		} else {
			ops[0] = 0xd3;     /* OUT (n),A */
			ops[1] = chk_v1(calc_val(operand + 1));
		}
	}
	return(2);
}

/*
 *      Die Funktion behandelt den IN Op-Code
 */
op_in()
{
	char *get_second();
	register char *p1, *p2;
	register int op;

	if (pass == 1) {                /* PASS 1 */
		if (*label)
			put_label();
	} else {                        /* PASS 2 */
		p1 = operand;
		p2 = tmp;
		while (*p1 != ',' && *p1 != '\0')
			*p2++ = *p1++;
		*p2 = '\0';
		switch (op = get_reg(tmp)) {
		case REGA:
			if (strncmp(operand, "A,(C)", 5) == 0) {
				ops[0] = 0xed;     /* IN A,(C) */
				ops[1] = 0x78;
			} else {
				ops[0] = 0xdb;     /* IN A,(n) */
				ops[1] = chk_v1(calc_val(get_second(operand) + 1));
			}
			break;
		case REGB:                      /* IN B,(C) */
		case REGC:                      /* IN C,(C) */
		case REGD:                      /* IN D,(C) */
		case REGE:                      /* IN E,(C) */
		case REGH:                      /* IN H,(C) */
		case REGL:                      /* IN L,(C) */
			ops[0] = 0xed;
			ops[1] = 0x40 + (op << 3);
			break;
		default:                /* ungueltiger Operand */
			ops[0] = 0;
			ops[1] = 0;
			asmerr(E_ILLOPE);
		}
	}
	return(2);
}

/*
 *      Diese Funktion behandelt den SET Op-Code
 */
op_set()
{
	char *strchr();
	register char *p1, *p2;
	register int len;
	register int i;
	register int op;

	len = 2;
	i = 0;
	if (pass == 1)
		if (*label)
			put_label();
	ops[0] = 0xcb;
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	if (pass == 2) {
		i = eval(tmp);
		if (i < 0 || i > 7)
			asmerr(E_VALOUT);
	}
	switch (op = get_reg(++p1)) {
	case REGA:                      /* SET n,A */
	case REGB:                      /* SET n,B */
	case REGC:                      /* SET n,C */
	case REGD:                      /* SET n,D */
	case REGE:                      /* SET n,E */
	case REGH:                      /* SET n,H */
	case REGL:                      /* SET n,L */
	case REGIHL:                    /* SET n,(HL) */
		ops[1] = 0xc0 + i * 8 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p1, "(IX+", 4) == 0) {
			len = 4;        /* SET n,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0xc6 + i * 8;
			}
		} else if (strncmp(p1, "(IY+", 4) == 0) {
			len = 4;        /* SET n,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0xc6 + i * 8;
			}
		} else {
			ops[1] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Diese Funktion behandelt den RES Op-Code
 */
op_res()
{
	char *strchr();
	register char *p1, *p2;
	register int len;
	register int i;
	register int op;

	len = 2;
	i = 0;
	if (pass == 1)
		if (*label)
			put_label();
	ops[0] = 0xcb;
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	if (pass == 2) {
		i = eval(tmp);
		if (i < 0 || i > 7)
			asmerr(E_VALOUT);
	}
	switch (op = get_reg(++p1)) {
	case REGA:                      /* RES n,A */
	case REGB:                      /* RES n,B */
	case REGC:                      /* RES n,C */
	case REGD:                      /* RES n,D */
	case REGE:                      /* RES n,E */
	case REGH:                      /* RES n,H */
	case REGL:                      /* RES n,L */
	case REGIHL:                    /* RES n,(HL) */
		ops[1] = 0x80 + i * 8 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p1, "(IX+", 4) == 0) {
			len = 4;        /* RES n,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x86 + i * 8;
			}
		} else if (strncmp(p1, "(IY+", 4) == 0) {
			len = 4;        /* RES n,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x86 + i * 8;
			}
		} else {
			ops[1] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Diese Funktion behandelt den BIT Op-Code
 */
op_bit()
{
	char *strchr();
	register char *p1, *p2;
	register int len;
	register int i;
	register int op;

	len = 2;
	i = 0;
	if (pass == 1)
		if (*label)
			put_label();
	ops[0] = 0xcb;
	p1 = operand;
	p2 = tmp;
	while (*p1 != ',' && *p1 != '\0')
		*p2++ = *p1++;
	*p2 = '\0';
	if (pass == 2) {
		i = eval(tmp);
		if (i < 0 || i > 7)
			asmerr(E_VALOUT);
	}
	switch (op = get_reg(++p1)) {
	case REGA:                      /* BIT n,A */
	case REGB:                      /* BIT n,B */
	case REGC:                      /* BIT n,C */
	case REGD:                      /* BIT n,D */
	case REGE:                      /* BIT n,E */
	case REGH:                      /* BIT n,H */
	case REGL:                      /* BIT n,L */
	case REGIHL:                    /* BIT n,(HL) */
		ops[1] = 0x40 + i * 8 + op;
		break;
	case NOREG:                     /* Operand ist kein Register */
		if (strncmp(p1, "(IX+", 4) == 0) {
			len = 4;        /* BIT n,(IX+d) */
			if (pass == 2) {
				ops[0] = 0xdd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x46 + i * 8;
			}
		} else if (strncmp(p1, "(IY+", 4) == 0) {
			len = 4;        /* BIT n,(IY+d) */
			if (pass == 2) {
				ops[0] = 0xfd;
				ops[1] = 0xcb;
				ops[2] = chk_v2(calc_val(strchr(operand, '+') + 1));
				ops[3] = 0x46 + i * 8;
			}
		} else {
			ops[1] = 0;
			asmerr(E_ILLOPE);
		}
		break;
	case NOOPERA:                   /* Operand fehlt */
		ops[1] = 0;
		asmerr(E_MISOPE);
		break;
	default:                        /* ungueltiger Operand */
		ops[1] = 0;
		asmerr(E_ILLOPE);
	}
	return(len);
}

/*
 *      Die Funktion liefert einen Pointer auf den zweiten Operanden
 *      bei Befehlen der Form: Op-Code   destination,source
 *      Fehlt ,source wird ein NULL-Pointer geliefert.
 */
char *get_second(s)
register char *s;
{
	char *strchr();
	register char *p;

	if ((p = strchr(s, ',')) != NULL)
		return(p + 1);
	else
		return(NULL);
}

/*
 *      Die Funktion bestimmt den Wert eines Reststrings der
 *      Form: expression)
 *      Z.B.: LD A,(IX+7)
 *                     --
 */
calc_val(s)
register char *s;
{
	register char *p;
	register int i;
	char *strrchr(), *strncpy();

	if ((p = strrchr(s, ')')) == NULL) {
		asmerr(E_MISPAR);
		return(0);
	}
	i = p - s;
	strncpy(tmp, s, i);
	*(tmp + i) = '\0';
	return(eval(tmp));
}
