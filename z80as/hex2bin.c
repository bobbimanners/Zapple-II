/*************************************************************
 * Convert Intel HEX file to BIN format
 * Bobbi
 * Oct 8 2019
 *************************************************************/

#include <stdio.h>
#include <string.h>
#include <ctype.h>

#undef DEBUG
#define FNAMELEN 15

/* Convert hex character to value
 * Returns value or 127 on error */
char hexchar(char c) {
    c = toupper(c);
    if ((c >= '0') && (c <= '9')) return c - '0';
    if ((c >= 'A') && (c <= 'F')) return c - 'A' + 10;
    return 127;
}

/* Do the actual work of converting a HEX file to a BIN file
 * Returns 0 on success, 1 on error, 2 on EOF */
char hextobin(FILE *in, FILE *out) {
    int c, datalen, addr, rectype, i;
    char byte;
    static int endaddr = -1;

    /* Each line starts with a colon */
    c = fgetc(in);
    if (c == -1) return 1;
    if (c != ':') {
        puts("Expected :");
        return 1;
    }

    /* Then two hex digits representing the data length */
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    datalen = c * 16;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    datalen += c;

#ifdef DEBUG
    printf("datalen=%d\n", datalen);
#endif

    /* Then four hex digits representing the address */
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    addr = c * 16 * 16 * 16;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    addr += c * 16 * 16;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    addr += c * 16;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    addr += c;

#ifdef DEBUG
    printf("addr=%d\n", addr);
#endif

    /* Then two more hex digits representing the record type */
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    rectype = c * 16;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    rectype += c;

#ifdef DEBUG
    printf("rectype=%d\n", rectype);
#endif

    /* We only support record type 0 (data) and 1 (EOF) */
    if ((rectype != 0) && (rectype != 1)) {
        printf("Unsupported record type %d\n", rectype);
        return 1;
    }

    /* Handle EOF record */
    if (rectype == 1) {
        return 2;
    }

    /* Initialize endaddr on first call */
    if (endaddr == -1) endaddr = addr;

    /* Check for overlapping addresses */
    if (addr < endaddr) {
        puts("Overlap in data!");
        return 1;
    }

    /* Zero fill gaps */
    if (addr > endaddr) {
        for (i = 0; i < addr - endaddr; ++i) {
            puts("FILL");
            fputc(0, out);
        }
    }

    endaddr = addr + datalen;

    /* Now datalen bytes stored as 2*datalen hex digits */
    for (i = 0; i < datalen; ++i) {
        c = fgetc(in);
        if (c == -1) return 1;
        c = hexchar(c);
        if (c == 127) return 1;
        byte = c * 16;
        c = fgetc(in);
        if (c == -1) return 1;
        c = hexchar(c);
        if (c == 127) return 1;
        byte += c;
        fputc(byte, out);        
    }

    /* Finally two checksum hex digits (ignored) */
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;
    c = fgetc(in);
    if (c == -1) return 1;
    c = hexchar(c);
    if (c == 127) return 1;

    /* Now eat the newline */
    c = fgetc(in);

    return 0;
}

int main(argc, argv)
int argc;
char *argv[];
{
    char len, ret;
    char inname[FNAMELEN+1], outname[FNAMELEN+1];
    FILE *in, *out;

    if (argc != 2) {
        puts("usage: hex2bin hexfile");
        return 1;
    }

    /* Strip off .HEX extension, if provided */
    len = strlen(argv[1]);
    if (len > 4) {
        if (((argv[1][len-1] == 'x') && (argv[1][len-2] == 'e') &&
             (argv[1][len-3] == 'h') && (argv[1][len-4] == '.')) ||
            ((argv[1][len-1] == 'X') && (argv[1][len-2] == 'E') &&
             (argv[1][len-3] == 'H') && (argv[1][len-4] == '.')))
            argv[1][len-4] = '\0';
    }

    strcpy(inname, argv[1]);
    strcat(inname, ".hex");
    strcpy(outname, argv[1]);
    strcat(outname, ".bin");
    printf("%s -> %s\n", inname, outname);

    in = fopen(inname, "r");
    if (!in) {
        printf("Can't open %s for reading\n", inname);
        goto done;
    }

    out = fopen(outname, "w");
    if (!out) {
        printf("Can't open %s for writing\n", outname);
        goto done;
    }

    while (!feof(in)) {
        ret = hextobin(in, out);
        putchar('.');
        if (ret == 1) {
            printf("Error parsing %s\n", inname);
            goto done;
        }
        if (ret == 2) {
            puts("Done.");
            goto done;
        }
    }
    return 0;

done:
    if (in) fclose(in);
    if (out) fclose(out);
    return 0;
}


