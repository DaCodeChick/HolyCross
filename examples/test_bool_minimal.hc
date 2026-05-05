// Minimal Bool test

Bool TestFunc() {
    return 1;
}

U0 Main() {
    Bool x;
    x = TestFunc();
    
    if (x) {
        "Bool works!\n";
    }
}
