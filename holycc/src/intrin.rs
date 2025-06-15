use dynasmrt::{DynasmApi, DynasmLabelApi, dynasm};

fn asm_memcpy(dst: *mut u8, src: *const u8, len: usize) {
    let mut ops = dynasmrt::Assembler::new().unwrap();
    dynasm!(ops
        ; mov rdi, dst
        ; mov rsi, src
        ; mov rcx, len
        ; rep movsb
    );
}
