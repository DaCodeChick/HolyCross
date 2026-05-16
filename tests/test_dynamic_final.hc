extern I64 getpid();
extern I64 getppid();

I64 _start() {
    I64 pid = getpid();
    I64 ppid = getppid();
    // Both should return positive values
    return 0;
}
