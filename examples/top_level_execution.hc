// Top-Level Statement Execution Example
// HolyC allows statements at the top level that execute when a file is loaded.
// This is a key feature of TempleOS where files can execute initialization code.

U0 InitSystem() {
    I64 initialized = 1;
}

U0 LoadConfig() {
    I64 config = 100;
}

U0 Main() {
    I64 main_started = 42;
}

// These statements execute when the file is loaded, BEFORE Main() is called:
InitSystem;
LoadConfig;
