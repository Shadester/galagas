/* The AGA data: tools/gen_assets.py --aga makes it, the bootblock reads it into chip RAM on an AGA machine only (after the game on the disk). All offsets are bytes from
 * the start of the block; the three bitmaps of 6 planes follow the block (size bytes after its start). */
#ifndef AGA_H
#define AGA_H
typedef struct {
    char magic[4];                               /* "AGA1" */
    unsigned long size;                          /* the size of the block, a multiple of 512 */
    unsigned long nspr;                          /* the number of sprites (the same ids as assets.h) */
    unsigned long spr_off;                       /* SpriteInfo[nspr] (assets.h), for 6 planes */
    unsigned long words_off;                     /* the sprite words, 6 planes */
    unsigned long pal_off;                       /* the palette of the game: 64 longs 0x00RRGGBB */
    unsigned long tpal_off;                      /* the palette of the title picture: 64 longs */
    unsigned long title_off;                     /* the title picture: 6 planes interleaved, like title_words */
} AgaHeader;
#define AGA_NPL 6
#endif
