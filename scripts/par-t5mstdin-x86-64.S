# G6.161: фізичний packed D24/T5M із stdin в edi, без host-декодера.
# Машинний bootstrap: після strict decode переходить на _start+5
# уже згенерованого ELF. pair_jump rel32 патчить лише Pascal postpass.
# Вхід 5 байт: 24 двійкові трити + фінальний термінатор 2.
# EINTR повторюється, short-read доповнюється; suffix EOF обов'язковий.
.intel_syntax noprefix
.text
.global stdin_start
stdin_start:
sub rsp, 16
xor ebx, ebx
xor r12d, r12d
read_more:
xor eax,eax
xor edi,edi
lea rsi,[rsp+r12]
mov edx,5
sub edx,r12d
syscall
cmp rax,-4
je read_more
test rax,rax
jle fail
add r12,rax
cmp r12,5
jb read_more
read_eof:
xor eax,eax
xor edi,edi
lea rsi,[rsp+5]
mov edx,1
syscall
cmp rax,-4
je read_eof
test rax,rax
jne fail
movzx ecx,byte ptr [rsp+0]
cmp ecx,162
jae fail
cmp ecx,81
jb bit_skip_0
sub ecx,81
bts ebx,23
bit_skip_0:
cmp ecx,54
jae fail
cmp ecx,27
jb bit_skip_1
sub ecx,27
bts ebx,22
bit_skip_1:
cmp ecx,18
jae fail
cmp ecx,9
jb bit_skip_2
sub ecx,9
bts ebx,21
bit_skip_2:
cmp ecx,6
jae fail
cmp ecx,3
jb bit_skip_3
sub ecx,3
bts ebx,20
bit_skip_3:
cmp ecx,2
jae fail
cmp ecx,1
jb bit_skip_4
sub ecx,1
bts ebx,19
bit_skip_4:
movzx ecx,byte ptr [rsp+1]
cmp ecx,162
jae fail
cmp ecx,81
jb bit_skip_5
sub ecx,81
bts ebx,18
bit_skip_5:
cmp ecx,54
jae fail
cmp ecx,27
jb bit_skip_6
sub ecx,27
bts ebx,17
bit_skip_6:
cmp ecx,18
jae fail
cmp ecx,9
jb bit_skip_7
sub ecx,9
bts ebx,16
bit_skip_7:
cmp ecx,6
jae fail
cmp ecx,3
jb bit_skip_8
sub ecx,3
bts ebx,15
bit_skip_8:
cmp ecx,2
jae fail
cmp ecx,1
jb bit_skip_9
sub ecx,1
bts ebx,14
bit_skip_9:
movzx ecx,byte ptr [rsp+2]
cmp ecx,162
jae fail
cmp ecx,81
jb bit_skip_10
sub ecx,81
bts ebx,13
bit_skip_10:
cmp ecx,54
jae fail
cmp ecx,27
jb bit_skip_11
sub ecx,27
bts ebx,12
bit_skip_11:
cmp ecx,18
jae fail
cmp ecx,9
jb bit_skip_12
sub ecx,9
bts ebx,11
bit_skip_12:
cmp ecx,6
jae fail
cmp ecx,3
jb bit_skip_13
sub ecx,3
bts ebx,10
bit_skip_13:
cmp ecx,2
jae fail
cmp ecx,1
jb bit_skip_14
sub ecx,1
bts ebx,9
bit_skip_14:
movzx ecx,byte ptr [rsp+3]
cmp ecx,162
jae fail
cmp ecx,81
jb bit_skip_15
sub ecx,81
bts ebx,8
bit_skip_15:
cmp ecx,54
jae fail
cmp ecx,27
jb bit_skip_16
sub ecx,27
bts ebx,7
bit_skip_16:
cmp ecx,18
jae fail
cmp ecx,9
jb bit_skip_17
sub ecx,9
bts ebx,6
bit_skip_17:
cmp ecx,6
jae fail
cmp ecx,3
jb bit_skip_18
sub ecx,3
bts ebx,5
bit_skip_18:
cmp ecx,2
jae fail
cmp ecx,1
jb bit_skip_19
sub ecx,1
bts ebx,4
bit_skip_19:
movzx ecx,byte ptr [rsp+4]
cmp ecx,162
jae fail
cmp ecx,81
jb bit_skip_20
sub ecx,81
bts ebx,3
bit_skip_20:
cmp ecx,54
jae fail
cmp ecx,27
jb bit_skip_21
sub ecx,27
bts ebx,2
bit_skip_21:
cmp ecx,18
jae fail
cmp ecx,9
jb bit_skip_22
sub ecx,9
bts ebx,1
bit_skip_22:
cmp ecx,6
jae fail
cmp ecx,3
jb bit_skip_23
sub ecx,3
bts ebx,0
bit_skip_23:
cmp ecx,2
jne fail
shl ebx,8
sar ebx,8
mov edi,ebx
add rsp,16
pair_jump:
.byte 0xe9,0,0,0,0
fail:
mov edi,2
mov eax,60
syscall
