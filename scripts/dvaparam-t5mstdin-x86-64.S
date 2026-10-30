# G6.175 — машинний D24 stdin (2×5 canonical packed T5M, 10 bytes).
# Signed two's complement D24 → EDI/ESI, тоді чинний compiler CALL.
# 0/short/trailing/trit2/term!=2: exit(2) без stdout. EINTR retry.
# Код НЕ встановлює семантику D5 чи лексичні D7 імена.
.intel_syntax noprefix
.text
.global stdin_pair_start
stdin_pair_start:
    sub rsp, 32
    xor r12d, r12d
read_more:
    xor eax, eax
    xor edi, edi
    lea rsi, [rsp+r12]
    mov edx, 10
    sub edx, r12d
    syscall
    cmp rax, -4
    je read_more
    test rax, rax
    jle fail
    add r12, rax
    cmp r12, 10
    jb read_more
read_eof:
    xor eax, eax
    xor edi, edi
    lea rsi, [rsp+10]
    mov edx, 1
    syscall
    cmp rax, -4
    je read_eof
    test rax, rax
    jne fail
    lea rsi, [rsp]
    call decode5
    mov r13d, eax
    lea rsi, [rsp+5]
    call decode5
    mov esi, eax
    mov edi, r13d
    add rsp, 32
pair_jump:
    .byte 0xe9,0,0,0,0
# Машинна база 3: чотири повні байти 5 двійкових тритів,
# п'ятий: 4 двійкові трити і рівно кінцева цифра 2.
.macro bit weight, position
    cmp ecx, (2*\weight)
    jae fail
    cmp ecx, \weight
    jb .Lskip\@
    sub ecx, \weight
    bts ebx, \position
.Lskip\@:
.endm
.macro full_byte idx
    movzx ecx, byte ptr [rsi+\idx]
    bit 81, (23-\idx*5)
    bit 27, (22-\idx*5)
    bit 9, (21-\idx*5)
    bit 3, (20-\idx*5)
    bit 1, (19-\idx*5)
.endm
decode5:
    xor ebx, ebx
    full_byte 0
    full_byte 1
    full_byte 2
    full_byte 3
    movzx ecx, byte ptr [rsi+4]
    bit 81, 3
    bit 27, 2
    bit 9, 1
    bit 3, 0
    cmp ecx, 2
    jne fail
    shl ebx, 8
    sar ebx, 8
    mov eax, ebx
    ret
fail:
    mov edi, 2
    mov eax, 60
    syscall
