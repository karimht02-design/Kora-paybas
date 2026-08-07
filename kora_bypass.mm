// kora_bypass.mm — Ultimate Plain Dylib for ESign Injection
// No Theos/Substrate dependency — direct Mach-O dylib
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <signal.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

// ==========================
// OBFUSCATION CONFIG
// ==========================
static const uintptr_t XOR_KEY = 0x9E3779B9;

// Encrypted offsets (original ^ XOR_KEY)
// 0x000a45ed ^ 0x9E3779B9 = 0x9E373C54
// 0x000a0299 ^ 0x9E3779B9 = 0x9E377B20
// 0x000ccc02 ^ 0x9E3779B9 = 0x9E37B5BB
static const uintptr_t ENC_OFF[3] = {
    0x9E373C54,  // sensitivity offset
    0x9E377B20,  // aim assist offset
    0x9E37B5BB   // recoil offset
};

// Encrypted values (original ^ XOR_KEY)
// 0x42c80000 ^ 0x9E3779B9 = 0xDC4FB9B9
// 0x3f800000 ^ 0x9E3779B9 = 0xA1B779B9
// 0x00000000 ^ 0x9E3779B9 = 0x9E3779B9
static const uint32_t ENC_VAL[3] = {
    0xDC4FB9B9,  // 99.0f
    0xA1B779B9,  // 1.0f
    0x9E3779B9   // 0.0f
};

__attribute__((always_inline, visibility("hidden")))
static inline uintptr_t dec_addr(uintptr_t v) {
    return v ^ XOR_KEY;
}

__attribute__((always_inline, visibility("hidden")))
static inline uint32_t dec_val(uint32_t v) {
    return v ^ XOR_KEY;
}

// ==========================
// ANTI-DEBUG
// ==========================
__attribute__((visibility("hidden")))
static bool is_debugged(void) {
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    if (sysctl(mib, 4, &info, &info_size, NULL, 0) == -1)
        return false;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

// ==========================
// SAFE MEMORY PATCHING
// ==========================
static jmp_buf g_jb;
static volatile sig_atomic_t g_can_jump = 0;

__attribute__((visibility("hidden")))
static void signal_handler(int sig) {
    (void)sig;
    if (g_can_jump) {
        g_can_jump = 0;
        siglongjmp(g_jb, 1);
    }
}

__attribute__((visibility("hidden")))
static bool is_valid_address(uintptr_t addr) {
    vm_address_t address = (vm_address_t)addr;
    vm_size_t size = 0;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    vm_region_basic_info_data_64_t info;
    memory_object_name_t object_name;

    kern_return_t kr = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                                     (vm_region_info_t)&info, &count, &object_name);
    if (kr != KERN_SUCCESS) return false;
    if (addr < address || addr >= address + size) return false;
    return (info.protection & VM_PROT_WRITE) || (info.protection & VM_PROT_COPY);
}

__attribute__((visibility("hidden")))
static bool safe_write(uintptr_t addr, uint32_t value) {
    if (addr == 0 || !is_valid_address(addr)) return false;
    if (is_debugged()) return false;

    struct sigaction old_segv, old_bus, sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_NODEFER;

    sigaction(SIGSEGV, &sa, &old_segv);
    sigaction(SIGBUS, &sa, &old_bus);

    bool success = false;
    g_can_jump = 1;
    if (sigsetjmp(g_jb, 1) == 0) {
        volatile uint32_t *ptr = (volatile uint32_t *)addr;
        *ptr = value;
        success = true;
    }
    g_can_jump = 0;

    sigaction(SIGSEGV, &old_segv, NULL);
    sigaction(SIGBUS, &old_bus, NULL);
    return success;
}

// ==========================
// BASE ADDRESS (ASLR BYPASS)
// ==========================
__attribute__((visibility("hidden")))
static uintptr_t get_image_base(void) {
    Dl_info info;
    void *header = dlsym(RTLD_DEFAULT, "_mh_execute_header");
    if (header && dladdr(header, &info)) {
        return (uintptr_t)info.dli_fbase;
    }
    return 0;
}

// ==========================
// MAIN PATCH LOGIC
// ==========================
__attribute__((visibility("hidden")))
static void apply_patches(void) {
    uintptr_t base = get_image_base();
    if (base == 0) return;

    for (int i = 0; i < 3; i++) {
        uintptr_t offset = dec_addr(ENC_OFF[i]);
        uint32_t value = dec_val(ENC_VAL[i]);
        safe_write(base + offset, value);
    }
}

// ==========================
// CONSTRUCTOR — STEALTH ENTRY
// ==========================
__attribute__((constructor))
static void initialize(void) {
    // Anti-debug: if debugger attached, do nothing
    if (is_debugged()) return;

    // Random delay: 5-15 seconds (harder to pattern-match)
    uint32_t delay = 5 + (arc4random() % 11);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        apply_patches();
    });
}
