monitor:
	clang -g -O0 -framework Hypervisor monitor.c -o monitor
exec:
	clang -c exec.s
	gobjcopy -O binary exec.o exec
clean:
	rm -rf exec.o exec monitor monitor.dSYM
