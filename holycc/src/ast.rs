enum BinaryOp {
    Add,
    AddAssign,
    And,
    AndAssign,
    Assign,
    BitAnd,
    BitOr,
    Div,
    DivAssign,
    Eq,
    Gt,
    GtEq,
    Lt,
    LtEq,
    Mod,
    ModAssign,
    Mul,
    MulAssign,
    NEq,
    Or,
    OrAssign,
    Sub,
    SubAssign,
    Xor,
    XorAssign,
}

struct Function {
    name: usize,           // Hash of the function name
    params: Vec<Variable>, // Vec of (type hash, identifier hash, value)
    return_type: usize,    // Type hash for the return type
    body: Vec<Statement>,  // Function body as a vector of statements
}

enum UnaryOp {
    Neg,
    Not,
}

enum Value {
    Bool(bool),
    Char(char),
    F64(f64),
    I16(i16),
    I32(i32),
    I64(i64),
    I8(i8),
    Identifier(usize), // Hash of the identifier
    Null,
    Ptr(usize), // Hash of the identifier
    Ref(usize), // Hash of the identifier
    String(String),
    U16(u16),
    U32(u32),
    U64(u64),
    U8(u8),
}

enum Statement {
    BinOp(Value, BinaryOp, Value),
    Block(Vec<Statement>),
    For(Box<Statement>, Box<Statement>, Box<Statement>), // Init, condition, increment
    If(Box<Statement>, Box<Statement>, Option<Box<Statement>>), // Condition, then block, else block
    Return(Box<Statement>),                              // Return value
    Switch(Box<Statement>, Vec<(Value, Box<Statement>)>), // Value, cases
    UnaryOp(UnaryOp, Value),
    Val(Value),
    VarDecl(Variable),                     // Variable declaration
    While(Box<Statement>, Box<Statement>), // Condition, body
}

struct Variable(usize, usize, Statement); // Type hash, identifier hash, value
