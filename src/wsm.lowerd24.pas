{ G6.96 — зниження ТІЛА SENS у машинний код із РЕКУРСІЄЮ.
  Тіло розбирається тим самим ParseD2WordsWide, що й обчислювач, і
  перекладається в x86-64 для підмножини:

    <параметр>              → mov eax, edi
    (як-є <D24>)            → mov eax, imm32
    (додати A B)            → gen A; push; gen B; mov ecx,eax; pop; add
    (відняти A B)           → те саме з sub
    (менше? A B)            → cmp + setl + movzx  (точний D1)
    (за-умовою …)           → гілки зверху вниз, «так» = інакше
    (<власне імʼя> X)       → самовиклик через call

  Угода виклику (host-механізм, не закон SENS): аргумент в edi,
  результат в eax; функція зберігає rdi (push/pop у пролозі).

  Поза підмножиною — ЯВНА відмова, без «майже правильно». }
unit wsm.lowerd24;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  ELowerD24Error = class(Exception);

{ BodyPhysical — packed T5M байти ТІЛА (функція з одним параметром).
  ParamPhysical — точний D7-ключ параметра, ArgPhysical — D24-аргумент.
  SelfPhysical — точний D7-ключ власного імені ('' — самовиклик заборонено).
  Результат — ELF64 ET_EXEC: exit(low8(тіло(аргумент))). }
function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;
function LowerBodyWithSelfELF(const BodyPhysical, ParamPhysical,
  ArgPhysical, SelfPhysical: RawByteString): RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.numericplane;

const
  ELFBase = $400000;
  HeaderBytes = 64 + 56;
  MaxCodeBytes = 4096;
  D24Width = 24;

function UkrBytes(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

procedure Need(Ok: Boolean; const Why: UnicodeString);
begin
  if not Ok then raise ELowerD24Error.Create(UkrBytes(Why));
end;

function BitsToLong(const Bits: RawByteString; out Value: LongWord): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  Value := 0;
  if Length(Bits) > 32 then Exit;
  for I := 1 to Length(Bits) do begin
    Need((Bits[I] = '0') or (Bits[I] = '1'), 'слово містить не двійковий знак');
    Value := (Value shl 1) or LongWord(Ord(Bits[I]) - Ord('0'));
  end;
  Result := True;
end;

function IsGlyphSequence(Node: TD2Node): Boolean;
var
  I: SizeInt;
begin
  Result := False;
  if (Node = nil) or (Node.Kind <> dkList) or (Length(Node.Children) = 0) then Exit;
  for I := 0 to High(Node.Children) do
    if (Node.Children[I].Kind <> dkIdentity) or (Node.Children[I].Width <> 7) then Exit;
  Result := True;
end;

function GlyphBits(Node: TD2Node): RawByteString;
var
  I: SizeInt;
begin
  Result := '';
  for I := 0 to High(Node.Children) do Result := Result + Node.Children[I].Bits;
end;

type
  TCodeBuf = array[0..MaxCodeBytes - 1] of Byte;

procedure Compile(const Node: TD2Node; const ParamBits, SelfBits: RawByteString;
  const FuncOffset: SizeInt; const TempDepth: SizeInt;
  var Code: TCodeBuf; var At: SizeInt);
var
  Head, Clause, Test: TD2Node;
  Value: LongWord;
  Width, K, JneAt, I: SizeInt;
  Delta: LongInt;
  IsElse: Boolean;
  Jumps: array of SizeInt;

  procedure Emit(const Bytes: array of Byte);
  var
    J: SizeInt;
  begin
    Need(At + Length(Bytes) <= MaxCodeBytes, 'згенерований код задовгий');
    for J := 0 to High(Bytes) do begin
      Code[At] := Bytes[J];
      Inc(At);
    end;
  end;

  procedure EmitImm32(const Opcode: Byte; const V: LongWord);
  begin
    Emit([Opcode, Byte(V and $FF), Byte((V shr 8) and $FF),
      Byte((V shr 16) and $FF), Byte((V shr 24) and $FF)]);
  end;

  procedure PatchRel32(const AtOpcode: SizeInt);
  begin
    Delta := At - (AtOpcode + 5);
    Code[AtOpcode + 1] := Byte(Delta and $FF);
    Code[AtOpcode + 2] := Byte((Delta shr 8) and $FF);
    Code[AtOpcode + 3] := Byte((Delta shr 16) and $FF);
    Code[AtOpcode + 4] := Byte((Delta shr 24) and $FF);
  end;

begin
  Need(Node <> nil, 'порожній вузол тіла');
  if IsGlyphSequence(Node) then begin
    if GlyphBits(Node) <> ParamBits then
      raise ELowerD24Error.Create(UkrBytes('імʼя поза параметрами: ' +
        RawByteString(GlyphBits(Node))));
    Emit([$89, $F8]);                       { mov eax, edi }
    Exit;
  end;
  Need(Node.Kind = dkList, 'тіло мусить бути списком або параметром');
  Need(Length(Node.Children) >= 1, 'порожній список у тілі');
  Head := Node.Children[0];
  Need(Head <> nil, 'порожня голова в тілі');
  { Голова-ІМʼЯ: або самовиклик, або явна відмова. Перевіряємо ДО вимоги
    «голова — координата», бо вузол-імʼя сам є списком. }
  if IsGlyphSequence(Head) then begin
    Need((SelfBits <> '') and (GlyphBits(Head) = SelfBits),
      'виклик чужого визначення поза підмножиною зниження');
    Need(Length(Node.Children) = 2, 'самовиклик приймає рівно один аргумент');
    { Аргумент обчислюється з edi (наш параметр), тому зберігаємо edi
      навколо виклику: каллі зберігає власний rdi, але не наш. }
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    Delta := FuncOffset - (At + 5);
    Emit([$E8, Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
      Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
    Emit([$5F]);                            { pop rdi — відновити наш n }
    Exit;
  end;
  Need(Head.Kind = dkIdentity, 'голова мусить бути координатою');
  Width := Head.Width;

  if (Width = 3) and (Head.Bits = '001') then begin
    Need(Length(Node.Children) = 2, 'цитата приймає рівно один аргумент');
    Need(Node.Children[1].Kind = dkIdentity, 'цитата тут лише над атомом');
    Need(BitsToLong(Node.Children[1].Bits, Value), 'літерал ширший за 32 біти');
    EmitImm32($B8, Value);                  { mov eax, imm32 }
    Exit;
  end;

  if (Width = 5) and ((Head.Bits = '01010') or (Head.Bits = '01011')) then begin
    Need(Length(Node.Children) = 3, 'арифметика приймає рівно два аргументи');
    if TempDepth = 0 then begin
      { Глибина 0: лівий операнд живе в rbx — жодного звертання до стеку.
        rbx зберігається і прологом функції, і самовикликом. }
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$89, $C3]);                     { mov ebx, eax }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      if Head.Bits = '01010' then Emit([$01, $D8])   { add eax, ebx }
      else begin
        Emit([$29, $C3]);                   { sub ebx, eax }
        Emit([$89, $D8]);                   { mov eax, ebx }
      end;
    end else begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$89, $C1]);                     { mov ecx, eax }
      Emit([$58]);                          { pop rax }
      if Head.Bits = '01010' then Emit([$01, $C8]) else Emit([$29, $C8]);
    end;
    Exit;
  end;

  if (Width = 5) and (Head.Bits = '11010') then begin
    Need(Length(Node.Children) = 3, 'менше? приймає рівно два аргументи');
    if TempDepth = 0 then begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$89, $C3]);                     { mov ebx, eax }
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, 1, Code, At);
      Emit([$39, $D8]);                     { cmp ebx, eax }
    end else begin
      Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$50]);
      Compile(Node.Children[2], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      Emit([$89, $C1]);
      Emit([$58]);
      Emit([$39, $C8]);                     { cmp eax, ecx }
    end;
    Emit([$0F, $9C, $C0]);                  { setl al }
    Emit([$0F, $B6, $C0]);                  { movzx eax, al }
    Exit;
  end;

  if (Width = 3) and (Head.Bits = '110') then begin
    Need(Length(Node.Children) >= 2, 'за-умовою потребує бодай одну гілку');
    Jumps := nil;
    for K := 1 to High(Node.Children) do begin
      Clause := Node.Children[K];
      Need((Clause <> nil) and (Clause.Kind = dkList) and
        (Length(Clause.Children) = 2), 'гілка мусить бути (тест тіло)');
      Test := Clause.Children[0];
      IsElse := (Test <> nil) and (Test.Kind = dkIdentity) and
        (Test.Width = 1) and (Test.Bits = '1');
      JneAt := -1;
      if not IsElse then begin
        Compile(Test, ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
        Emit([$83, $F8, $01]);              { cmp eax, 1 }
        JneAt := At;
        Emit([$0F, $85, $00, $00, $00, $00]); { jne next }
      end;
      Compile(Clause.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
      SetLength(Jumps, Length(Jumps) + 1);
      Jumps[High(Jumps)] := At;
      Emit([$E9, $00, $00, $00, $00]);      { jmp end }
      { jne — ШЕСТИбайтна форма (0F 85 + rel32), тому кінець = +6. }
      if JneAt >= 0 then begin
        Delta := At - (JneAt + 6);
        Code[JneAt + 2] := Byte(Delta and $FF);
        Code[JneAt + 3] := Byte((Delta shr 8) and $FF);
        Code[JneAt + 4] := Byte((Delta shr 16) and $FF);
        Code[JneAt + 5] := Byte((Delta shr 24) and $FF);
      end;
    end;
    Emit([$31, $C0]);                       { xor eax, eax — вичерпання }
    for I := 0 to High(Jumps) do begin
      Delta := At - (Jumps[I] + 5);
      Code[Jumps[I] + 1] := Byte(Delta and $FF);
      Code[Jumps[I] + 2] := Byte((Delta shr 8) and $FF);
      Code[Jumps[I] + 3] := Byte((Delta shr 16) and $FF);
      Code[Jumps[I] + 4] := Byte((Delta shr 24) and $FF);
    end;
    Exit;
  end;

  if IsGlyphSequence(Head) then begin
    Need((SelfBits <> '') and (GlyphBits(Head) = SelfBits),
      'виклик чужого визначення поза підмножиною зниження');
    Need(Length(Node.Children) = 2, 'самовиклик приймає рівно один аргумент');
    { Аргумент обчислюється з edi (наш параметр), тому зберігаємо edi
      навколо виклику: каллі зберігає власний rdi, але не наш. }
    Emit([$57]);                            { push rdi }
    Compile(Node.Children[1], ParamBits, SelfBits, FuncOffset, TempDepth + 1, Code, At);
    Emit([$89, $C7]);                       { mov edi, eax }
    Delta := FuncOffset - (At + 5);
    Emit([$E8, Byte(Delta and $FF), Byte((Delta shr 8) and $FF),
      Byte((Delta shr 16) and $FF), Byte((Delta shr 24) and $FF)]);
    Exit;
  end;

  raise ELowerD24Error.Create(UkrBytes(
    'форма поза підмножиною зниження: параметр, (як-є D24), додати, ' +
    'відняти, менше?, за-умовою, самовиклик'));
end;

{ D7 ім'я в ABI цього lowering — один непорожній D2-список
  точних 7-бітових фізичних слів, а не конкатенація довільних слів.
  Не декодуємо людинозрозумілі назви та не визначаємо тут мовний закон. }
function StripNameBits(const Physical: RawByteString): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(Physical, Words);
  Need(Length(Words) >= 3, 'фізичне D7-імʼя має бути непорожнім списком');
  Need((Words[0] = '10') and (Words[High(Words)] = '01'),
    'фізичне D7-імʼя потребує точних D2-меж');
  Result := '';
  for I := 1 to High(Words) - 1 do begin
    Need(Length(Words[I]) = 7, 'усі слова D7-імені мусять бути 7-бітові');
    Result := Result + Words[I];
  end;
end;

function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;
begin
  Result := LowerBodyWithSelfELF(BodyPhysical, ParamPhysical, ArgPhysical, '');
end;

function LowerBodyWithSelfELF(const BodyPhysical, ParamPhysical,
  ArgPhysical, SelfPhysical: RawByteString): RawByteString;
var
  BodyWords, ArgWords: TExactWords;
  Doc: TD2Document;
  Code: TCodeBuf;
  At, I, FuncOffset, CallFixAt, FileSize: SizeInt;
  Arg: LongWord;
  ParamBits, SelfBits: RawByteString;
  Delta: LongInt;

  procedure Put(Offset: SizeInt; Number: QWord; Width: SizeInt);
  var
    K: SizeInt;
  begin
    for K := 0 to Width - 1 do begin
      Result[Offset + K + 1] := AnsiChar(Byte(Number and $FF));
      Number := Number shr 8;
    end;
  end;

begin
  Result := '';
  ParamBits := StripNameBits(ParamPhysical);
  Need(Length(ParamBits) > 0, 'ключ параметра порожній');
  SelfBits := '';
  if SelfPhysical <> '' then SelfBits := StripNameBits(SelfPhysical);

  DecodeT5M(ArgPhysical, ArgWords);
  Need(Length(ArgWords) = 1, 'аргумент мусить бути одним словом');
  Need(Length(ArgWords[0]) = D24Width, 'аргумент мусить бути точним D24');
  Need(BitsToLong(ArgWords[0], Arg), 'аргумент не влазить у 32 біти');

  DecodeT5M(BodyPhysical, BodyWords);
  Doc := ParseD2WordsWide(BodyWords);
  try
    Need(Length(Doc.Roots) = 1, 'тіло мусить мати рівно один корінь');
    At := 0;
    { _start: 5 + 5 + 2 + 3 + 5 + 2 = 22 байти. }
    Code[0] := $BF;                                   { mov edi, arg32 }
    Code[1] := Byte(Arg and $FF);
    Code[2] := Byte((Arg shr 8) and $FF);
    Code[3] := Byte((Arg shr 16) and $FF);
    Code[4] := Byte((Arg shr 24) and $FF);
    Code[5] := $E8;                                   { call F }
    CallFixAt := 5;
    Code[6] := 0; Code[7] := 0; Code[8] := 0; Code[9] := 0;
    Code[10] := $89; Code[11] := $C7;                 { mov edi, eax }
    Code[12] := $83; Code[13] := $E7; Code[14] := $FF; { and edi, 255 }
    Code[15] := $B8; Code[16] := $3C;                 { mov eax, 60 }
    Code[17] := $00; Code[18] := $00; Code[19] := $00;
    Code[20] := $0F; Code[21] := $05;                 { syscall }
    FuncOffset := 22;
    At := FuncOffset;
    Code[At] := $57; Inc(At);                         { push rdi — зберегти n }
    Code[At] := $53; Inc(At);                         { push rbx — тимчасовий }
    Compile(Doc.Roots[0], ParamBits, SelfBits, FuncOffset, 0, Code, At);
    Code[At] := $5B; Inc(At);                         { pop rbx }
    Code[At] := $5F; Inc(At);                         { pop rdi }
    Code[At] := $C3; Inc(At);                         { ret }

    Delta := FuncOffset - (CallFixAt + 5);
    Code[CallFixAt + 1] := Byte(Delta and $FF);
    Code[CallFixAt + 2] := Byte((Delta shr 8) and $FF);
    Code[CallFixAt + 3] := Byte((Delta shr 16) and $FF);
    Code[CallFixAt + 4] := Byte((Delta shr 24) and $FF);

    FileSize := HeaderBytes + At;
    SetLength(Result, FileSize);
    for I := 1 to Length(Result) do Result[I] := #0;
    Put(0, $464C457F, 4);
    Put(4, 2, 1); Put(5, 1, 1); Put(6, 1, 1);
    Put(16, 2, 2); Put(18, 62, 2); Put(20, 1, 4);
    Put(24, ELFBase + HeaderBytes, 8);
    Put(32, 64, 8);
    Put(52, 64, 2); Put(54, 56, 2); Put(56, 1, 2);
    Put(64, 1, 4); Put(68, 5, 4);
    Put(80, ELFBase, 8); Put(88, ELFBase, 8);
    Put(96, FileSize, 8); Put(104, FileSize, 8); Put(112, $1000, 8);
    for I := 0 to At - 1 do
      Result[HeaderBytes + I + 1] := AnsiChar(Code[I]);
  finally
    Doc.Free;
  end;
end;

end.
