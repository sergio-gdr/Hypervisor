hyper:
	llvm-gcc -framework Hypervisor hyper.c -o hyper
mbr:
	llvm-gcc -pipe  -ffreestanding -mpreferred-stack-boundary=2  -mno-mmx -mno-3dnow -mno-sse -mno-sse2 -mno-sse3  -c mbr.s
	llvm-gcc -pipe  -ffreestanding -mpreferred-stack-boundary=2  -mno-mmx -mno-3dnow -mno-sse -mno-sse2 -mno-sse3  -N -e entry -Ttext=0x600 -Wl,-S,--oformat,binary -nostdlib -o mbr mbr.o
