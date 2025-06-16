use anywho::Result;
use dynasmrt::{Assembler, DynasmApi, DynasmLabelApi, dynasm};

/// Finds the position of the least significant set bit.
fn hc_bsf(assembler: &mut Assembler, bit_field_val: i64) -> i64 {
    dynasm!(assembler
        ; mov eax, bit_field_val
        ; bsf eax, eax
        ; mov bit_field_val, eax
    );
    bit_field_val
}

/// Finds the position of the most significant set bit.
fn hc_bsr(assembler: &mut Assembler, bit_field_val: i64) -> i64 {
    dynasm!(assembler
        ; mov eax, bit_field_val
        ; bsr eax, eax
        ; mov bit_field_val, eax
    );
    bit_field_val
}

/// Tests if a specific bit is set.
fn hc_bt(assembler: &mut Assembler, bit_field: &[u8], bit: i64) -> bool {
    dynasm!(assembler
        ; mov rax, bit_field
        ; mov rbx, bit
        ; bt [rax], rbx
        ; setc al
    );
    DynasmApi::get_reg(assembler, 0) != 0
}

/// Tests if a specific bit is set and clears it if it was set.
fn hc_btc(assembler: &mut Assembler, bit_field: &[u8], bit: i64) -> bool {
    dynasm!(assembler
        ; mov rax, bit_field
        ; mov rbx, bit
        ; btc [rax], rbx
        ; setc al
    );
    DynasmApi::get_reg(assembler, 0) != 0
}

/// Tests if a specific bit is set and clears it if it was set, returning the original value.
fn hc_btr(assembler: &mut Assembler, bit_field: &[u8], bit: i64) -> i64 {
    dynasm!(assembler
        ; mov rax, bit_field
        ; mov rbx, bit
        ; btr [rax], rbx
        ; mov rax, [rax]
    );
    DynasmApi::get_reg(assembler, 0)
}

/// Tests if a specific bit is set and sets it if it was not set.
fn hc_bts(assembler: &mut Assembler, bit_field: &[u8], bit: i64) -> bool {
    dynasm!(assembler
        ; mov rax, bit_field
        ; mov rbx, bit
        ; bts [rax], rbx
        ; setc al
    );
}

/// Tests if a specific bit is set and clears it if it was set.
fn hc_lbtc(assembler: &mut Assembler, value: usize) -> usize {
    dynasm!(assembler
        ; mov eax, value
        ; lbtc eax, eax
        ; mov value, eax
    );
    value
}

/// Tests if a specific bit is set and clears it if it was set, returning the original value.
fn hc_lbtr(assembler: &mut Assembler, value: usize) -> usize {
    dynasm!(assembler
        ; mov eax, value
        ; lbtr eax, eax
        ; mov value, eax
    );
    value
}

/// Tests if a specific bit is set and sets it if it was not set.
fn hc_lbts(assembler: &mut Assembler, value: usize) -> usize {
    dynasm!(assembler
        ; mov eax, value
        ; lbts eax, eax
        ; mov value, eax
    );
    value
}

/// Copies memory from one location to another.
fn hc_memcpy(assembler: &mut Assembler, dst: *mut u8, src: *const u8, len: usize) {
    dynasm!(assembler
        ; mov rdi, dst
        ; mov rsi, src
        ; mov rcx, len
        ; rep movsb
    );
}

/// Compares two 64-bit integers and returns the minimum.
fn hc_mini64(assembler: &mut Assembler, lhs: i64, rhs: i64) -> i64 {
    dynasm!(assembler
        ; mov rax, lhs
        ; cmp rax, rhs
        ; cmovl rax, rhs
        ; mov lhs, rax
    );
}

/// Swaps the byte order of a 32-bit integer.
fn hc_swapu32(assembler: &mut Assembler, value: u32) -> u32 {
    dynasm!(assembler
        ; mov eax, value
        ; bswap eax
        ; mov value, eax
    );
    value
}
