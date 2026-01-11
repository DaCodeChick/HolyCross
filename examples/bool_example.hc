// Example demonstrating boolean values and NULL pointers
// In HolyC, Bool/TRUE/FALSE/NULL are typically defined in stdlib
// For this example, we use U8 for boolean values

U0 Main() {
    U8 is_ready = 1;    // TRUE
    U8 is_done = 0;     // FALSE
    U8 *ptr = 0;        // NULL
    
    if (is_ready && !is_done) {
        is_ready = 2;  // Mark as processed
    }
    
    if (ptr == 0) {
        is_done = 1;  // Mark done if pointer is null
    }
}
