// Test that __DIR__ expands in code

// This should expand __DIR__ to "examples" and use it
#define TEST_VAL __DIR__

U0 Main() {
    // If __DIR__ wasn't expanded, this would fail as an undefined identifier
    // If it is expanded, it becomes a string literal "examples"
}
