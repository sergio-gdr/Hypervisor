hyper:
	clang -framework Hypervisor hyper.c -o hyper
exec:
	clang -pipe  -ffreestanding -mno-mmx -mno-3dnow -mno-sse -mno-sse2 -mno-sse3  -c exec.s
	gobjcopy -O binary exec.o exec
