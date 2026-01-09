// Example demonstrating Bool, TRUE, FALSE, and NULL
// Note: These are NOT keywords in HolyC - they're defined in the standard library:
//   class Bool:U8;
//   #define TRUE 1
//   #define FALSE 0
//   #define NULL 0
// The lexer treats them as regular identifiers, not reserved words.

U0 Main() {
    Bool is_ready = TRUE;
    Bool is_done = FALSE;
    U8 *ptr = NULL;
    
    if (is_ready && !is_done) {
        "System is ready!\n";
    }
    
    if (ptr == NULL) {
        "Pointer is null\n";
    }
}
