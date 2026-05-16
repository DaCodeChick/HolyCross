USE64

_start::
    MOV RAX, 60      // sys_exit
    MOV RDI, 42      // exit code
    SYSCALL
