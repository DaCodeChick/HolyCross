// Example demonstrating Bool, TRUE, FALSE, and NULL keywords
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
