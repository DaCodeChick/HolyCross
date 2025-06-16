use core::hash;
use std::collections::HashMap;
use std::mem::size_of;

/// Binary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
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

const PTR_HASH: usize = hash_identifier("*");
const REF_HASH: usize = hash_identifier("&");

/// Class representation
#[derive(Debug, Clone)]
pub struct Class {
    name: String,                  // Class name
    hash: usize,                   // Hash
    fields: Vec<Variable>,         // Vec of (type hash, identifier hash, value)
    instances: Vec<ClassInstance>, // Vec of class instances
}

impl Class {
    /// Create a new class with the given name
    pub fn new(name: usize) -> Self {
        Class {
            name,
            fields: Vec::new(),
            instances: Vec::new(),
        }
    }

    /// Add a field to the class
    pub fn add_field(&mut self, field: Variable) {
        self.fields.push(field);
    }

    /// Add an instance to the class
    pub fn add_instance(&mut self, instance: ClassInstance) {
        self.instances.push(instance);
    }
}

/// Class instance representation
#[derive(Debug, Clone)]
pub struct ClassInstance {
    name: String,             // Instance name
    type_hash: usize,         // Hash of the instance type
    value: Option<Statement>, // Value associated with the instance
}

/// Function representation
#[derive(Debug, Clone)]
pub struct Function {
    name: String,          // Name of the function
    hash: usize,           // Hash of the function
    params: Vec<Variable>, // Vec of (type hash, identifier hash, value)
    return_type: usize,    // Type hash for the return type
    stack_offset: usize,   // Stack offset for the function
    body: Vec<Statement>,  // Function body as a vector of statements
}

impl Function {
    /// Create a new function with the given name and return type
    pub fn new(name: usize, return_type: usize) -> Self {
        Function {
            name,
            params: Vec::new(),
            return_type,
            body: Vec::new(),
        }
    }

    /// Add a parameter to the function
    pub fn add_param(&mut self, param: Variable) {
        self.params.push(param);
    }

    /// Add a statement to the function body
    pub fn add_statement(&mut self, statement: Statement) {
        self.body.push(statement);
    }
}

/// Function call representation
#[derive(Debug, Clone)]
pub struct FunctionCall {
    name: String,         // Name of the function
    args: Vec<Statement>, // Arguments passed to the function
    return_type: usize,   // Type hash for the return type
}

impl FunctionCall {
    /// Create a new function call with the given name and return type
    pub fn new(name: &str, return_type: usize) -> Self {
        FunctionCall {
            name: name.to_string(),
            args: Vec::new(),
            return_type,
        }
    }

    /// Add an argument to the function call
    pub fn add_arg(&mut self, arg: Statement) {
        self.args.push(arg);
    }

    /// Compile-time evaluation of the function call
    pub fn compile_time_eval(&self) -> Option<Value> {
        let mut result = None;
        for arg in &self.args {
            if let Some(value) = arg.compile_time_eval() {
                result = Some(value);
            }
        }
        for body in &self.body {
            if let Some(value) = body.compile_time_eval() {
                result = Some(value);
            }
        }
        result
    }
}

/// Unary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,
    Not,
}

/// Value representation
#[derive(Debug, Clone)]
pub enum Value {
    Array(Statement),  // Array value
    Bool(bool),        // Boolean value
    Char(char),        // Character value
    F64(f64),          // 64-bit floating point value
    I16(i16),          // 16-bit integer value
    I32(i32),          // 32-bit integer value
    I64(i64),          // 64-bit integer value
    I8(i8),            // 8-bit integer value
    Identifier(usize), // Hash of the identifier
    Null,              // Null value
    Ptr(usize, usize), // Pointer, with the AST holding a depth value and identifier hash
    Ref(usize, usize), // Reference, with the AST holding a depth value and identifier hash
    String(String),    // String value
    U16(u16),          // 16-bit unsigned integer value
    U32(u32),          // 32-bit unsigned integer value
    U64(u64),          // 64-bit unsigned integer value
    U8(u8),            // 8-bit unsigned integer value
}

/// Statement representation
#[derive(Debug, Clone)]
pub enum Statement {
    Asm(String),                                                // Inline assembly statement
    BinOp(Value, BinaryOp, Value),                              // Left value, operator, right value
    Block(Vec<Statement>),                                      // Block of statements
    Break,                                                      // Break statement
    Call(FunctionCall),                                         // Function call
    ClassDecl(Class),                                           // Class declaration
    Continue,                                                   // Continue statement
    For(Box<Statement>, Box<Statement>, Box<Statement>), // Initialization, condition, increment
    If(Box<Statement>, Box<Statement>, Option<Box<Statement>>), // Condition, then block, optional else block
    Return(Box<Statement>),                                     // Return statement
    Switch(Box<Statement>, Vec<(Value, Box<Statement>)>),       // Switch statement with cases
    UnaryOp(UnaryOp, Value),                                    // Operator, value
    Val(Value),                                                 // Value statement
    VarDecl(Variable),                                          // Variable declaration
    While(Box<Statement>, Box<Statement>),                      // Condition, body
}

impl Statement {
    /// Evaluate the statement at compile time
    pub fn compile_time_eval(&self) -> Option<Value> {
        match self {
            Statement::Val(value) => Some(value.clone()),
            Statement::UnaryOp(op, value) => match (op, value) {
                (UnaryOp::Neg, Value::I32(i)) => Some(Value::I32(-i)),
                (UnaryOp::Neg, Value::I64(i)) => Some(Value::I64(-i)),
                (UnaryOp::Neg, Value::I16(i)) => Some(Value::I16(-i)),
                (UnaryOp::Neg, Value::I8(i)) => Some(Value::I8(-i)),
                (UnaryOp::Neg, Value::U32(i)) => Some(Value::U32(-(*i as i32) as u32)),
                (UnaryOp::Neg, Value::U64(i)) => Some(Value::U64(-(*i as i64) as u64)),
                (UnaryOp::Neg, Value::U16(i)) => Some(Value::U16(-(*i as i16) as u16)),
                (UnaryOp::Neg, Value::U8(i)) => Some(Value::U8(-(*i as i8) as u8)),
                (UnaryOp::Neg, Value::F64(f)) => Some(Value::F64(-f)),
                (UnaryOp::Neg, Value::Char(c)) => Some(Value::Char(-(*c as i8) as char)),
                (UnaryOp::Not, Value::Bool(b)) => Some(Value::Bool(!b)),
                _ => None,
            },
            Statement::BinOp(left, op, right) => match (left, right, op) {
                (Value::I32(l), Value::I32(r), BinaryOp::Add) => Some(Value::I32(l + r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Sub) => Some(Value::I32(l - r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Mul) => Some(Value::I32(l * r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Div) => Some(Value::I32(l / r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Mod) => Some(Value::I32(l % r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::I32(l), Value::I32(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::I32(l), Value::I32(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::I32(l), Value::I32(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::I32(l), Value::I32(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Add) => Some(Value::I64(l + r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Sub) => Some(Value::I64(l - r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Mul) => Some(Value::I64(l * r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Div) => Some(Value::I64(l / r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Mod) => Some(Value::I64(l % r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::I64(l), Value::I64(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::I64(l), Value::I64(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::I64(l), Value::I64(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::I64(l), Value::I64(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Add) => Some(Value::I16(l + r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Sub) => Some(Value::I16(l - r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Mul) => Some(Value::I16(l * r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Div) => Some(Value::I16(l / r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Mod) => Some(Value::I16(l % r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::I16(l), Value::I16(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::I16(l), Value::I16(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::I16(l), Value::I16(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::I16(l), Value::I16(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Add) => Some(Value::I8(l + r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Neg) => Some(Value::I8(-l)),
                (Value::I8(l), Value::I8(r), BinaryOp::Sub) => Some(Value::I8(l - r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Mul) => Some(Value::I8(l * r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Div) => Some(Value::I8(l / r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Mod) => Some(Value::I8(l % r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::I8(l), Value::I8(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::I8(l), Value::I8(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::I8(l), Value::I8(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::I8(l), Value::I8(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Add) => Some(Value::U32(l + r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Sub) => Some(Value::U32(l - r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Mul) => Some(Value::U32(l * r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Div) => Some(Value::U32(l / r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Mod) => Some(Value::U32(l % r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::U32(l), Value::U32(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::U32(l), Value::U32(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::U32(l), Value::U32(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::U32(l), Value::U32(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Add) => Some(Value::U64(l + r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Sub) => Some(Value::U64(l - r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Mul) => Some(Value::U64(l * r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Div) => Some(Value::U64(l / r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Mod) => Some(Value::U64(l % r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::U64(l), Value::U64(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::U64(l), Value::U64(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::U64(l), Value::U64(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::U64(l), Value::U64(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Add) => Some(Value::U16(l + r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Sub) => Some(Value::U16(l - r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Mul) => Some(Value::U16(l * r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Div) => Some(Value::U16(l / r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Mod) => Some(Value::U16(l % r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::U16(l), Value::U16(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::U16(l), Value::U16(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::U16(l), Value::U16(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::U16(l), Value::U16(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Add) => Some(Value::U8(l + r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Sub) => Some(Value::U8(l - r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Mul) => Some(Value::U8(l * r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Div) => Some(Value::U8(l / r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Mod) => Some(Value::U8(l % r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Eq) => Some(Value::Bool(l == r)),
                (Value::U8(l), Value::U8(r), BinaryOp::NEq) => Some(Value::Bool(l != r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Gt) => Some(Value::Bool(l > r)),
                (Value::U8(l), Value::U8(r), BinaryOp::Lt) => Some(Value::Bool(l < r)),
                (Value::U8(l), Value::U8(r), BinaryOp::GtEq) => Some(Value::Bool(l >= r)),
                (Value::U8(l), Value::U8(r), BinaryOp::LtEq) => Some(Value::Bool(l <= r)),
            },
            Statement::Block(statements) => {
                let mut result = None;
                statements.iter().for_each(|stmt| {
                    if let Some(value) = stmt.compile_time_eval() {
                        result = Some(value);
                    }
                });
                result
            }
            Statement::For(init, cond, step, body) => {
                let mut result = None;
                if let Some(value) = init.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = cond.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = step.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = body.compile_time_eval() {
                    result = Some(value);
                }
                result
            }
            Statement::While(cond, body) => {
                let mut result = None;
                if let Some(value) = cond.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = body.compile_time_eval() {
                    result = Some(value);
                }
                result
            }
            Statement::If(cond, then_branch, else_branch) => {
                let mut result = None;
                if let Some(value) = cond.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = then_branch.compile_time_eval() {
                    result = Some(value);
                }
                if let Some(value) = else_branch.compile_time_eval() {
                    result = Some(value);
                }
                result
            }
            Statement::Return(value) => {
                if let Some(val) = value.compile_time_eval() {
                    Some(val)
                } else {
                    None
                }
            }
            Statement::Switch(expr, cases) => {
                let mut result = None;
                if let Some(value) = expr.compile_time_eval() {
                    result = Some(value);
                }
                for (case_value, case_body) in cases {
                    if let Some(case_val) = case_value.compile_time_eval() {
                        if case_val == result.unwrap_or(Value::Null) {
                            if let Some(body_val) = case_body.compile_time_eval() {
                                result = Some(body_val);
                            }
                        }
                    }
                }
                result
            }
            Statement::VarDecl(var) => {
                if let Some(value) = var.2.compile_time_eval() {
                    Some(value)
                } else {
                    None
                }
            }
            Statement::Call(call) => {
                let mut result = None;
                for arg in &call.args {
                    if let Some(value) = arg.compile_time_eval() {
                        result = Some(value);
                    }
                }
                result
            }
            _ => None,
        }
    }
}

pub struct Union {
    name: String,          // Name of the union
    hash: usize,           // Hash of the union
    fields: Vec<Variable>, // Fields of the union
}

/// Variable representation
#[derive(Debug, Clone)]
pub struct Variable {
    type_hash: usize,       // Type hash of the variable
    name: String,           // Name of the variable
    identifier_hash: usize, // Hash of the variable identifier
    stack_offset: usize,    // Stack offset for the variable
    value: Statement,       // Value associated with the variable
}

impl Variable {
    /// Create a new variable with the given type hash, name, and value
    pub fn new(type_hash: usize, name: &str, stack_offset: usize, value: Statement) -> Self {
        Self {
            type_hash,
            name: name.to_string(),
            identifier_hash: hash_identifier(name),
            stack_offset,
            value,
        }
    }

    /// Set the value of the variable
    pub fn set_value(&mut self, value: Statement) {
        self.value = value;
    }

    /// Get the identifier hash of the variable
    pub fn identifier_hash(&self) -> usize {
        self.identifier_hash
    }

    /// Get the type hash of the variable
    pub fn type_hash(&self) -> usize {
        self.type_hash
    }

    /// Get the stack offset of the variable
    pub fn stack_offset(&self) -> usize {
        self.stack_offset
    }
}

/// Abstract Syntax Tree (AST) representation
#[derive(Debug, Clone)]
pub struct AbstractSyntaxTree {
    classes: Vec<(usize, Class)>,      // Vec of classes (line number, class)
    functions: Vec<(usize, Function)>, // Vec of functions (line number, function)
    statements: Vec<Statement>,        // Top-level statements
    vars: Vec<(usize, Variable)>,      // Global variables (line number, variable)
}

impl AbstractSyntaxTree {
    /// Create a new empty AST
    pub fn new() -> Self {
        AbstractSyntaxTree {
            classes: Vec::new(),
            functions: Vec::new(),
            statements: Vec::new(),
            vars: Vec::new(),
        }
    }

    /// Add a class to the AST
    pub fn add_class(&mut self, class: Class) {
        if !self.check_type_hash_duplicate(class.name) {
            self.classes.push(class);
        }
    }

    /// Add a function to the AST
    pub fn add_function(&mut self, function: Function) {
        self.functions.push(function);
    }

    /// Add a global variable to the AST
    pub fn add_global_var(&mut self, var: Variable) {
        self.global_vars.push(var);
    }

    /// Add a top-level statement to the AST
    pub fn add_statement(&mut self, statement: Statement) {
        self.statements.push(statement);
    }

    const fn hash_ptr(ptr: Value) -> usize {
        hash_identifier("*") ^ ptr.hash()
    }

    fn check_identifier_duplicate(&self, identifier: &str) -> bool {
        let identifier_hash = hash_identifier(identifier);
        self.vars
            .iter()
            .any(|(_, var)| var.identifier_hash() == identifier_hash)
            || self
                .functions
                .iter()
                .any(|(_, func)| func.name == identifier_hash)
            || self
                .classes
                .iter()
                .any(|(_, class)| class.name == identifier_hash)
    }

    fn check_type_duplicate(&self, type_hash: usize) -> bool {
        self.classes
            .iter()
            .any(|(_, class)| class.name == type_hash);
    }
}

/// Hash an identifier to a usize
const fn hash_identifier(identifier: &str) -> usize {
    let mut hash = 0xcbf29ce484222325;
    identifier.as_bytes().iter().for_each(|&b| {
        hash ^= (b as usize).wrapping_mul(0x100000001B3);
    });
    hash
}
