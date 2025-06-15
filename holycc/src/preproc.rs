mod ast;
use ast::Statement;

enum Token {
    Assert(Statement), // Assert a condition in the code
    CmdLine,
    Date,
    Define(String, String), // Define a macro with name and text to replace
    File(String),           // Path to the source file
    HelpFile(String),       // Path to the help file
    HelpIndex(usize),       // Hash of the help index
    Include(String),
    Instance(String),
    Line(usize), // Line number in the source file
    Time,
}
