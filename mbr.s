/*
 * This 16-bit code is installed in the first
 * sector of the disk drive, which is loaded by
 * the BIOS when the disk-drive is selected for
 * booting.
 * Fundamentals:
 * When an IBM PC/AT or compatible computers are turned on, firmware (BIOS) is 
 * loaded to RAM and is start executing. The BIOS is a small and primitive 
 * operating system, in the sense that it builds fundamental data structures, 
 * such as interrupt table, and provides a standard interface to communicate 
 * with devices (device-drivers). MS-DOS relied on this for its functioning.
 * The fundamental problem with the BIOS is its legacy operating mode (16-bit
 * real-mode).
 * After BIOS is loaded and started, it will try to boot (bring up a modern
 * operating system) from different devices. We almost certainly will end up
 * booting from a secondary storage device (i.e a hard disk), ultimately 
 * reading into main memory the first sector of the device and transfering 
 * control to it. The present is the program assembled and copied to the 
 * first sector of the booting disk-drive, so only then we have control of the 
 * system. This program is usually refered as the Master Boot Record (MBR). 
 * There are some standards that date to the original IBM PC/AT functioning 
 * format that the MBR need to be aware of:
 * The essence is an ordered list of booting programs, each one bigger and 
 * more complex than the preceding. There are also some fundamental standards 
 * such as where in memory are these programs loaded, the format of some data 
 * structures, etc.
 * Some fundamentals of the architecture of the x86 processor is required.
 * Basically, the latest processors of the x86 (i386 or amd64) line are 
 * compatible with the original x86 processor, that is, the 8088. Being 
 * compatible means supporting the same instruction set and addressing modes.
 * When any IBM PC/at computer is powered on, its processor acts like a 
 * primitive 8088, in a mode known as real mode. 
 * Addressing in real mode is done through the tuple (off, s), where off 
 * is a logical offset, and s is the value of some segment register, that acts 
 * as a address base. So, to compute an address in this mode, 
 * we define:
 * Absolute: ((unsigned int )off, (unsigned int)s) -> a 
 * Absolute first shifts the 16-bit value s 4 bits to the left, forming a 
 * 20-bit base address, and then adds the 16-bit value off to it, forming a.
 * Finally, the absolute address is directly mapped to the corresponding 
 * physical address.
 * Actually, the situation gets a little more complex by the fact that the 
 * 8088 has an address width of 20-bits, and 80286 of 24-bits, but it's safe 
 * to ignore in the context of this program, because we are not interested in
 * the protected mode of the 80286.
 * With the previous backgroung, the following conventions and/or standards 
 * are to consider when booting an IBM PC/at compatible computer system:
 * BIOS:
 * - It is copied to the top of the physical address space, then it is also 
 *   mapped to the beginning of it.
 * - The API, used by early programs, is standard.
 * - The real-mode interrupt table is created at the beginning of the address 
 *   space.
 * - It copies the first sector of the hard-drive (MBR) to address 
 *   Absolute(0x7c00, 0) (See above).
 * - It transfers control to the MBR.
 * MBR:
 * - Has a standard format.
 * - Bytes 0 - 445 are for instructions.
 * - Bytes 446 - 511 are for the partition table.
 * - Loads a bigger program from the selected partition to address 
 *   Absolute(0x7c00, 0).
 * - Transfers control to the next booting program.
 */

.set	LDAD, 0x7c00 # address where this code is loaded
.set	REL, 0x600 # address where this code is going to be copied
.set	PARTT_OFF, 0x1be # offset to partition table
.set	MAGIC, 0x55aa
.set	TYPES_FS, 0x5
.set	TICKS, 0xb6

.globl	entry
.code16
entry:
/*
 * This is our very first instruction.
 * Its purpose is to jump above all the static data structure that follows.
 */
	jmp start # skip data structures
crlf: // end of line string
	.asciz	"\r\n"
ent_num: // Stores number of valid entries in the partition table
	.byte	0x00
parts_ids: // Read-only array of supported file-systems
	.byte	0xa5, 0x83, 0x07, 0x50
parts_strs_ptrs: // Read-only array of strings describing operating systems
	.word BSD_str, Linux_str, Win_str, SOS_str, unk_str
parts_strs:
unk_str:
	.asciz "Unk"
BSD_str:
	.asciz "BSD"
Linux_str:
	.asciz "Lin"
Win_str:
	.asciz "Win"
SOS_str:
	.asciz "SOS"
start:
/*
 * Because usually the next booting program expects to be loaded at 
 * Absolute(0x7c00, 0), virtually all MBR of known operating systems 
 * (FreeBSD, Linux...) do a 512-byte copy from Absolute(0x7c00, 0) to 
 * Absolute(y, 0), where y must be at least Absolute(0x7c00, 0) - 512,
 * so it does not overwrite itself while loading the next booting program.
 * We copy to Absolute(0x600, 0).
 */
	cli # no interrupts until stable stack
	cld # up we go for strings operations
	xorw %si, %si
	movw %si, %es # initialize (eliminate segmentation)
	movw %si, %ds #  segment registers
	movw %si, %ss #  except %cs
	movw $LDAD, %sp # stack starts at $LDAD
	sti # stable stack; set interrupts
	movw $REL, %di # copy to %di
	orw %sp, %si #  from %si
	movw $0x100, %cx #  256 words
	rep # do
	movsw #  it
	jmp main-LDAD+REL # intrasegment jump to relocated code
main:
/*
 * The partition table is scanned looking for familiar file-systems in each of 
 * its four entries. On each match, it stores the corresponding offset to the 
 * entry at the boot_queue data structure, it then looks for the character 
 * string that corresponds to the file-system of the entry, and prints
 * the name of the operating system.
 */
	pushw %dx # save BIOS drive number
	movw $(partt+4), %bx # bx point to partition table + 4
	jmp 2f
1:
	addb $0x10, %bl # next entry
	jc end_pt # carry if past 256 boundary
2:
	incb ent_num	# increment current entry
	movw $parts_ids, %di # scan through %di
	movw $TYPES_FS, %cx #  TYPES_FS times
	movw (%bx), %ax # search for entry match
	repne # do
	scasb	# it
	movw $TYPES_FS, %dx # number of partition types
	subw %cx, %dx #  less cx
	movw %dx, %cx #  == string offset
	pushw %bx # save partition offset
	movw $(parts_strs_ptrs-2), %bx # search for correct string for entry
2:
	addw $2, %bx # next pointer
	decb %cl
	jnz 2b
3:
	movw (%bx), %bx # extract pointer to string
	movb ent_num, %ah # number of entry
	addb $0x30, %ah # make it ascii
	movb %ah, one_char_str # copy byte to one-character string
	movw $one_char_str, %si # save string
	pushw %bx
	call putstr # print option
	popw %bx
	movw %bx, %si # we point to the correct string now
	call putstr
	movw $crlf, %si
	call putstr
	popw %bx # restore partition table offset
	jmp 1b # next entry
end_pt:
	movb $0, ent_num # restore default value
	xorb %ah, %ah # int 1ah 0
	int $0x1a # get time
	movw %dx, %di # copy
	addw $TICKS, %di # reference time
read_key:
	xorb %ah, %ah # int 1ah 0
	int $0x1a # get time
	cmpw %dx, %di # timeout?
	jb lst_sl # yes
	movb $1, %ah
	int $0x16
	jz read_key # if no input
	movb $0, %ah
	int $0x16
	subb $1, %ah # one less to match scan code with numbers
	cmpb $4, %ah # check
	ja read_key #  if
	cmpb $0, %ah #  correct
	jbe read_key #  selection
	movb %ah, last_sel # save last selection
lst_sl:
	movb last_sel, %ah # copy last selection
valid_key:
	movb %ah, %cl # copy number
	movw $partt, %si # %si point to partition table
	jmp 4f
3:
	addw $0x10, %si
4:
	loop 3b
read_blk:
	popw %dx # restore BIOS drive number
	movw $LDAD, %bx
	pushw %si # save entry pointer
	movw %sp, %di # also save stack pointer	
	pushl $0 #  construct 
	pushl 8(%si) #  data structure
	pushw %es #  to
	pushw %bx #  form	
	push $1 #  packet
	push $0x10 #  for
	movw %sp, %si #  LBA
	movb $0x42, %ah #  access	
1:
	int	$0x13 #  through BIOS
	jc error
	movw %di, %sp # restore stack
	movw $0x301, %ax # 1 sector/write function
	movw $1, %cx
	xorb %dh, %dh
	movw $0x600, %bx
	int $0x13 # write
	popw %si # also restore entry pointer
	jmp LDAD # jump to bootloader

/*
 * Prints string of characters by calling bios_int()
 * on each character.
 * Note that printing a single character corresponds
 * to printing a one character string.
 */
/* void putstr(char *) */
putstr:
	lodsb # load next byte
	testb %al, %al
	jz 2f
1:
	movb $0xe, %ah
	movb $7, %bh
	int $0x10
	jmp putstr
2:
	ret

error:
	jmp .
	
	.fill 167, 1, 0

one_char_str: // This defines the one-character string
	.byte	0x00, '.', ' ', 0x00
last_sel: // last selection
	.byte 0x01
partt:
	.byte 0x80, 0x01, 0x01, 0x00, 0xa5, 0xff, 0xff, 0xff, 0x3f, 0x00,  0x00, 0x00, 0xf5, 0xff, 0x1f, 0x03, 0x00, 0xfe, 0xff, 0xff, 0x50, 0xfe, 0xff, 0xff, 0x34, 0x00,  0x20, 0x03, 0xbd, 0xff, 0xdf, 0x0b, 0x00, 0xff, 0xff, 0xff, 0x0c, 0x0f, 0xe1, 0xff, 0x30, 0x00,  0x00, 0x0f, 0xc2, 0xf6, 0x46, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x55, 0xaa
