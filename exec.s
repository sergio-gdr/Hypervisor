.set LDAD, 0x7c00 # address where this code is loaded
.set REL, 0x600 # address where this code is going to be copied
.set PARTT_OFF, 0x1be # offset to partition table
.set MAGIC, 0x55aa
.set TYPES_FS, 0x5
.set TICKS, 0xb6

.globl entry
.code64
entry:
 movq $1, %rax
