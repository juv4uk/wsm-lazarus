{ G6.95 — ПЕРШЕ СПРАВЖНЄ ЗНИЖЕННЯ ТІЛА SENS У МАШИННИЙ КОД.
  Тіло (не host-код!) розбирається тим самим ParseD2WordsWide, що й
  обчислювач, і перекладається в x86-64 для ПІДМНОЖИНИ форм:

    <параметр>              → mov eax, edi
    (як-є <D24>)            → mov eax, imm32
    (додати A B)            → gen A; push rax; gen B; mov ecx,eax; pop rax; add eax,ecx
    (відняти A B)           → те саме з sub

  Поза підмножиною — ЯВНА відмова, без здогадів і без «майже правильно».

  Що це доводить: тіло з pinned/користувацького визначення стає нативним
  кодом, і його результат звіряється з ОБЧИСЛЮВАЧЕМ SENS як оракулом.
  Чого це не доводить: рекурсії, списків, змінних понад один параметр,
  GC, повного SENS. Це не компілятор SENS — це перший lowering. }
unit wsm.lowerd24;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  ELowerD24Error = class(Exception);

{ BodyPhysical — позичені packed T5M байти ТІЛА (функція з одним
  параметром). ParamPhysical — точний D7-ключ параметра (імʼя).
  ArgPhysical — точний D24-аргумент виклику.
  Результат — ELF64 ET_EXEC: exit(low8(тіло(аргумент))). }
function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.numericplane;

const
  ELFBase = $400000;
  HeaderBytes = 64 + 56;
  MaxCodeBytes = 512;
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

{ Компілятор підмножини: рекурсивний обхід AST із видачею байтів. }
procedure Compile(const Node: TD2Node; const ParamBits: RawByteString;
  var Code: array of Byte; var At: SizeInt);
var
  Head: TD2Node;
  Value: LongWord;
  Width: SizeInt;

  procedure Emit(const Bytes: array of Byte);
  var
    K: SizeInt;
  begin
    Need(At + Length(Bytes) <= MaxCodeBytes, 'згенерований код задовгий');
    for K := 0 to High(Bytes) do begin
      Code[At] := Bytes[K];
      Inc(At);
    end;
  end;

  procedure EmitImm32(const Opcode: Byte; const V: LongWord);
  begin
    Emit([Opcode, Byte(V and $FF), Byte((V shr 8) and $FF),
      Byte((V shr 16) and $FF), Byte((V shr 24) and $FF)]);
  end;

begin
  Need(Node <> nil, 'порожній вузол тіла');
  { Параметр: точна D7-послідовність, що дорівнює ключу параметра. }
  if IsGlyphSequence(Node) then begin
    Need(GlyphBits(Node) = ParamBits,
      'у тілі є імʼя, якого немає серед параметрів');
    Emit([$89, $F8]);                       { mov eax, edi }
    Exit;
  end;
  Need(Node.Kind = dkList, 'тіло мусить бути списком або параметром');
  Need(Length(Node.Children) >= 1, 'порожній список у тілі');
  Head := Node.Children[0];
  Need((Head <> nil) and (Head.Kind = dkIdentity), 'голова мусить бути координатою');
  Width := Head.Width;

  { (як-є <атом>) — точний літерал. }
  if (Width = 3) and (Head.Bits = '001') then begin
    Need(Length(Node.Children) = 2, 'цитата приймає рівно один аргумент');
    Need(Node.Children[1].Kind = dkIdentity, 'цитата тут лише над атомом');
    Need(BitsToLong(Node.Children[1].Bits, Value), 'літерал ширший за 32 біти');
    EmitImm32($B8, Value);                  { mov eax, imm32 }
    Exit;
  end;

  { (додати A B) / (відняти A B) }
  if (Width = 5) and ((Head.Bits = '01010') or (Head.Bits = '01011')) then begin
    Need(Length(Node.Children) = 3, 'арифметика приймає рівно два аргументи');
    Compile(Node.Children[1], ParamBits, Code, At);
    Emit([$50]);                            { push rax }
    Compile(Node.Children[2], ParamBits, Code, At);
    Emit([$89, $C1]);                       { mov ecx, eax }
    Emit([$58]);                            { pop rax }
    if Head.Bits = '01010' then Emit([$01, $C8])   { add eax, ecx }
    else Emit([$29, $C8]);                          { sub eax, ecx }
    Exit;
  end;

  raise ELowerD24Error.Create(UkrBytes(
    'форма поза підмножиною зниження: лише параметр, (як-є D24), додати, відняти'));
end;

function LowerBodyELF(const BodyPhysical, ParamPhysical,
  ArgPhysical: RawByteString): RawByteString;
var
  BodyWords, ParamWords, ArgWords: TExactWords;
  Doc: TD2Document;
  Code: array[0..MaxCodeBytes - 1] of Byte;
  At, I: SizeInt;
  Arg: LongWord;
  ParamBits: RawByteString;
  FileSize: SizeInt;

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
  DecodeT5M(ParamPhysical, ParamWords);
  { Ключ параметра — самі гліфи: обгортки вузла-імʼя `10 … 01` не
    належать до точного D7-ключа. }
  ParamBits := '';
  for I := 0 to High(ParamWords) do
    if (ParamWords[I] <> '10') and (ParamWords[I] <> '01') then
      ParamBits := ParamBits + ParamWords[I];
  Need(Length(ParamBits) > 0, 'ключ параметра порожній');

  DecodeT5M(ArgPhysical, ArgWords);
  Need(Length(ArgWords) = 1, 'аргумент мусить бути одним словом');
  Need(Length(ArgWords[0]) = D24Width, 'аргумент мусить бути точним D24');
  Need(BitsToLong(ArgWords[0], Arg), 'аргумент не влазить у 32 біти');

  DecodeT5M(BodyPhysical, BodyWords);
  Doc := ParseD2WordsWide(BodyWords);
  try
    Need(Length(Doc.Roots) = 1, 'тіло мусить мати рівно один корінь');
    At := 0;
    { _start: завантажити аргумент у edi, обчислити тіло, вийти low8. }
    Code[At] := $BF; Inc(At);              { mov edi, imm32 }
    Code[At] := Byte(Arg and $FF); Inc(At);
    Code[At] := Byte((Arg shr 8) and $FF); Inc(At);
    Code[At] := Byte((Arg shr 16) and $FF); Inc(At);
    Code[At] := Byte((Arg shr 24) and $FF); Inc(At);
    Compile(Doc.Roots[0], ParamBits, Code, At);
    Code[At] := $89; Inc(At); Code[At] := $C7; Inc(At);   { mov edi, eax }
    Code[At] := $83; Inc(At); Code[At] := $E7; Inc(At);
    Code[At] := $FF; Inc(At);                              { and edi, 255 }
    Code[At] := $B8; Inc(At);                              { mov eax, 60 }
    Code[At] := $3C; Inc(At);
    Code[At] := $00; Inc(At); Code[At] := $00; Inc(At);
    Code[At] := $00; Inc(At);
    Code[At] := $0F; Inc(At); Code[At] := $05; Inc(At);     { syscall }

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
