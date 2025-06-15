enum Token {
    Define(String, String),
    HelpIndex(usize), // Hash of the help index
    Include(String),
}
