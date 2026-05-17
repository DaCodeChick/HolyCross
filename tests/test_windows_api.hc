// Test Windows API imports from different DLLs
extern U0 ExitProcess(I64 exit_code);
extern I64 GetStdHandle(I64 std_handle);
extern I64 printf(U8 *fmt);
extern I64 malloc(I64 size);
extern U0 free(I64 ptr);

U0 _start() {
    // Mix of kernel32.dll and msvcrt.dll functions
    I64 handle;
    I64 mem;
    
    handle = GetStdHandle(-11);  // STD_OUTPUT_HANDLE, kernel32.dll
    
    printf("Hello from msvcrt!\n");  // msvcrt.dll
    
    mem = malloc(100);  // msvcrt.dll
    free(mem);          // msvcrt.dll
    
    ExitProcess(0);  // kernel32.dll
}
