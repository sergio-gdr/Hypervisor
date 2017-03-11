#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <Hypervisor/hv.h>
#include <Hypervisor/hv_error.h>
#include <Hypervisor/hv_vmx.h>

#define SEGM_SIZE 0xFFFF // size of real-mode segment
#define CTRL_HALT_INSTR (1<<7) // VM exit when guest executes halt instruction
#define CTRL_UNCON_IO (1<<24) // VM exit when guest executes IO instruction
#define CTRL_UNRSTR (1<<7) // unrestricted guest (execute in real mode)
#define CTRL_SECOND (1<<31) // enable secondary processor controls
#define BITMAP_1 (CTRL_HALT_INSTR | CTRL_UNCON_IO | CTRL_SECOND) // bitmap for primary processor-based ctrl
#define BITMAP_2 (CTRL_UNRSTR)

#define VM_MEM_MAP(uva, gpa, size, flags) \
 if ( (ret = hv_vm_map(uva, gpa, size, flags) != HV_SUCCESS)) { \
   print_err(ret); \
   exit(0); \
 }

#define HV_EXEC(vcpu) \
 if ( (ret = hv_vcpu_run(*vcpu)) != HV_SUCCESS) { \
  print_err(ret); \
  exit(0); \
 }

static void print_err(hv_return_t err)
{
 switch (err) {
  case HV_ERROR:
   printf("Error: HV_ERROR\n");
   break;
  case HV_BUSY:
   printf("Error: HV_BUSY\n");
   break;
  case HV_BAD_ARGUMENT:
   printf("Error: HV_BAD_ARGUMENT\n");
   break;
  case HV_NO_RESOURCES:
   printf("Error: HV_NO_RESOURCES\n");
   break;
  case HV_NO_DEVICE:
   printf("Error: HV_NO_DEVICE\n");
   break;
  case HV_UNSUPPORTED:
   printf("Error: HV_UNSUPPORTED\n");
   break;
  default:
   printf("Unknown Error\n");
 }
}

static void write_vmcs(hv_vcpuid_t *vcpu, uint32_t field, uint64_t value) {
 hv_return_t ret;

 if ( (ret = hv_vmx_vcpu_write_vmcs(*vcpu, field, value)) != HV_SUCCESS) {
  print_err(ret);
  exit(0);
 }
}

static void read_vmcs(hv_vcpuid_t *vcpu, uint32_t field, uint64_t *value) {
 hv_return_t ret;

 if ( (ret = hv_vmx_vcpu_read_vmcs(*vcpu, field, value)) != HV_SUCCESS) {
  print_err(ret);
  exit(0);
 }
}

static void read_caps(hv_vmx_capability_t field, uint64_t *value)
{
 hv_return_t ret;

 if ( (ret = hv_vmx_read_capability(field, value)) != HV_SUCCESS) {
  print_err(ret);
  exit(0);
 }
}

static void vmcs_init_ctrl(hv_vcpuid_t *vcpu)
{
 uint64_t cap;

 /* whatever can be 0, default to 0 (except what we want to enable) */

 read_caps(HV_VMX_CAP_PINBASED, &cap); // read capabilities of pin-based VM-execution controls
 write_vmcs(vcpu, VMCS_CTRL_PIN_BASED, (((cap >> 32) & cap) | 0x1) & 0xffffffff); // VM-exit on external interrupts

 read_vmcs(vcpu, HV_VMX_CAP_PROCBASED, &cap);
 write_vmcs(vcpu, VMCS_CTRL_CPU_BASED, (((cap >> 32) & cap) | BITMAP_1) & 0xffffffff);

 read_vmcs(vcpu, HV_VMX_CAP_PROCBASED2, &cap);
 write_vmcs(vcpu, VMCS_CTRL_CPU_BASED, (((cap >> 32) & cap) | BITMAP_2) & 0xffffffff);

 read_vmcs(vcpu, HV_VMX_CAP_ENTRY, &cap);
 write_vmcs(vcpu, VMCS_CTRL_VMENTRY_CONTROLS, ((cap >> 32) & cap)  & 0xffffffff);
}

/* incomplete */
static void vmcs_init_guest(hv_vcpuid_t *vcpu)
{
 write_vmcs(vcpu, VMCS_GUEST_RIP, 0);
 write_vmcs(vcpu, VMCS_GUEST_RSP, SEGM_SIZE);
 write_vmcs(vcpu, VMCS_GUEST_RFLAGS, 0);

 write_vmcs(vcpu, VMCS_GUEST_CS, 0);
 write_vmcs(vcpu, VMCS_GUEST_CS_BASE, 0);
 write_vmcs(vcpu, VMCS_GUEST_CS_LIMIT, SEGM_SIZE);
 write_vmcs(vcpu, VMCS_GUEST_DS, 0);
 write_vmcs(vcpu, VMCS_GUEST_DS_BASE, 0);
 write_vmcs(vcpu, VMCS_GUEST_DS_LIMIT, SEGM_SIZE);
 write_vmcs(vcpu, VMCS_GUEST_ES, 0);
 write_vmcs(vcpu, VMCS_GUEST_ES_BASE, 0);
 write_vmcs(vcpu, VMCS_GUEST_ES_LIMIT, SEGM_SIZE);
 write_vmcs(vcpu, VMCS_GUEST_SS, 0);
 write_vmcs(vcpu, VMCS_GUEST_SS_BASE, 0);
 write_vmcs(vcpu, VMCS_GUEST_SS_LIMIT, SEGM_SIZE);
}

int main(int argc, char *argv[])
{

 if (argc == 1) {
  printf("Supply file path as argument\n");
  exit(0);
 }

 hv_return_t ret;
 /* Create the VM */
 if ( (ret = hv_vm_create(HV_VM_DEFAULT)) != HV_SUCCESS) {
  print_err(ret);
  exit(0);
 }

 /* Create Virtual CPU. Can now manipulate vmcs. */
 hv_vcpuid_t *vcpu;
 if ( (ret = hv_vcpu_create(vcpu, HV_VCPU_DEFAULT)) != HV_SUCCESS) {
  print_err(ret);
  exit(0);
 }

 /* Set the vmcs guest area */
 vmcs_init_guest(vcpu);

 /* Set the vmcs control area */
 vmcs_init_ctrl(vcpu);

 /* Allocate page-aligned memory and map to guest address 0x0 */
 static void *mem_map;
 posix_memalign(&mem_map, 4096, SEGM_SIZE); // memory must be aligned to page boundary
 VM_MEM_MAP(mem_map, 0, SEGM_SIZE, HV_MEMORY_READ | HV_MEMORY_WRITE | HV_MEMORY_EXEC);

 /* open file to execute (no error checking) */
 struct stat file_stat;
 int raw_fd;
 raw_fd = open(argv[1], O_RDWR);
 fstat(raw_fd, &file_stat);
 read(raw_fd, mem_map, file_stat.st_size);
 close(raw_fd);

 uint64_t exit_reas;
 while (1) {
  HV_EXEC(vcpu);
  read_vmcs(vcpu, VMCS_RO_EXIT_REASON, &exit_reas);
  switch (exit_reas) {
   case VMX_REASON_HLT:
    ;
   case VMX_REASON_IO:
    ;
   default:
    ;
  }
 }
}