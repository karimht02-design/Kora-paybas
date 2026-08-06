#include <pthread.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/mman.h>
#include <mach/mach.h>
#include <dlfcn.h>

struct CheatConfig {
    bool AntiBan = true;
    float Sensitivity = 99.0f;
    float AimAssist = 1.0f;
    float Recoil = 0.0f;
} cfg;

uintptr_t get_base_address() {
    Dl_info info;
    void* header = dlsym(RTLD_DEFAULT, "_mh_execute_header");
    if (header && dladdr(header, &info)) {
        return (uintptr_t)info.dli_fbase;
    }
    return 0;
}

bool patch_memory(uintptr_t address, uint32_t value) {
    if (address == 0) return false;
    uintptr_t page_size = 0x4000;
    uintptr_t page_start = address & ~(page_size - 1);
    uintptr_t page_end = (address + sizeof(uint32_t) + page_size - 1) & ~(page_size - 1);
    size_t page_len = page_end - page_start;
    if (mprotect((void*)page_start, page_len, PROT_READ | PROT_WRITE) == 0) {
        *(volatile uint32_t*)address = value;
        mprotect((void*)page_start, page_len, PROT_READ | PROT_EXEC);
        return true;
    }
    kern_return_t kr = vm_protect(mach_task_self(), page_start, page_len, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) {
        *(volatile uint32_t*)address = value;
        vm_protect(mach_task_self(), page_start, page_len, false, VM_PROT_READ | VM_PROT_EXECUTE);
        return true;
    }
    return false;
}

void* init_kora_bypass(void* arg) {
    sleep(5);
    uintptr_t base = get_base_address();
    if (base == 0) return nullptr;
    if (cfg.Sensitivity > 0) {
        patch_memory(base + 0xa45ed, 0x42c80000);
    }
    if (cfg.AimAssist > 0) {
        patch_memory(base + 0xa0299, 0x3f800000);
    }
    if (cfg.Recoil == 0.0f) {
        patch_memory(base + 0xccc02, 0x00000000);
    }
    return nullptr;
}

__attribute__((constructor)) static void initialize() {
    pthread_t thread;
    pthread_create(&thread, nullptr, init_kora_bypass, nullptr);
}
