/*
 *      Z80 - Assembler
 *      Copyright (C) 1987-1992 by Udo Munk
 *
 *	History:
 *	17-SEP-1987 Development under Digital Research CP/M 2.2
 *      28-JUN-1988 Switched to Unix System V.3
 */

/*
 *	Extern Declaration der globalen Variablen
 */

extern char	*infiles[],
		objfn[],
		lstfn[],
		*srcfn,
		line[],
		tmp[],
		label[],
		opcode[],
		operand[],
		ops[],
		title[];

extern	int	list_flag,
		sym_flag,
		ver_flag,
		pc,
		pass,
		iflevel,
		gencode,
		errors,
		errnum,
		sd_flag,
		sd_val,
		prg_adr,
		prg_flag,
		out_form,
		symsize,
		no_opcodes,
		no_operands;

extern FILE	*srcfp,
		*objfp,
		*lstfp,
		*errfp;

extern unsigned	c_line,
		s_line,
		p_line,
		ppl,
		page;

extern struct sym *symtab[],
		  **symarray;

extern struct opc opctab[];

extern struct ope opetab[];
