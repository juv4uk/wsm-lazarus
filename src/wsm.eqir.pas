{ G6.53 — вузький перевірений ExactIR → D3:101(D1,D1) → ELF64.
  Усі координати походять тільки з pinned двійкового SENS Contract 12.
  Емітер споживає вже знижені операнди, а не переглядає .sens знову.
  Це НЕ загальний компілятор, D7/числа D12+/Core4 тут не виконуються. }
unit wsm.eqir;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

type
  EEqIRError = class(Exception);
  { Приватний результат зниження: host-значення двох D1-бітів.
    WordIndex — лише перевірена фізична адреса, не числовий SENS-операнд. }
  TLoweredD3Eq = record
    LeftBit, RightBit: Byte;
    HeadWord, LeftWord, RightWord: SizeInt;
  end;

procedure LowerPinnedD3Eq(const Physical, AuthorityRoot: RawByteString;
  out Operation: TLoweredD3Eq);
function BuildPinnedD3EqIRELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;

implementation
uses wsm.bind, wsm.domain, wsm.exactir, wsm.exactirguard,
  wsm.elfgeometry;

const
  HeaderBytes = 120;
  ELFBase: QWord = $400000;

procedure Require(Yes: Boolean; const Why: String);
begin
  if not Yes then raise EEqIRError.Create(Why);
end;

procedure LowerPinnedD3Eq(const Physical, AuthorityRoot: RawByteString;
  out Operation: TLoweredD3Eq);
var
  Tables: TDomainSet;
  IR: TExactIR;
  Stats: TExactIRGuardStats;
  Candidate: TLoweredD3Eq;
  I: SizeInt;
begin
  FillChar(Operation, SizeOf(Operation), 0);
  FillChar(Candidate, SizeOf(Candidate), 0);
  Require((Length(Physical) >= 1) and (Length(Physical) <= 65536),
    'Фізичний .sens поза межею перевіреного ELF');
  { Першоджерело: pinned домени, фізичний reader і один ExactIR.
    Структурний guard НЕ вирішує викличність — це окрема відмова нижче. }
  LoadPinnedDomains(AuthorityRoot, Tables);
  BuildExactIR(Physical, Tables, IR);
  VerifyExactIRStructure(IR, Stats);
  Require((Length(IR.Roots) = 1) and (IR.Roots[0] = 0) and
          (Length(IR.Nodes) = 4) and (IR.BoundLeaves = 3),
    'Потрібна одна точна двоаргументна форма D3:101');
  Require((IR.Nodes[0].Kind = ikList) and
          (IR.Nodes[0].ParentIndex = -1) and
          (IR.Nodes[0].SubtreeEndExclusive = 4), 
    'Виклик не є кореневим фізичним D2-списком');
  Require((IR.Nodes[1].Kind = ikIdentity) and IR.Nodes[1].HasKey
          and SameKey(IR.Nodes[1].Key, ExactKey('101')) and
          (IR.Nodes[1].ParentIndex = 0) and
          (IR.Nodes[1].ChildIndex = 0), 
    'Голова не є дозволеною точною D3:101');
  for I := 2 to 3 do begin
    Require((IR.Nodes[I].Kind = ikIdentity) and IR.Nodes[I].HasKey
            and (IR.Nodes[I].ParentIndex = 0) and
            (IR.Nodes[I].ChildIndex = I-1) and
            (IR.Nodes[I].Key.Width = 1) and
            (IR.Nodes[I].Key.Bits <= 1),
      'У цьому зрізі D3:101 допускає лише два точні D1 атоми');
  end;
  Candidate.LeftBit := Byte(IR.Nodes[2].Key.Bits);
  Candidate.RightBit := Byte(IR.Nodes[3].Key.Bits);
  Candidate.HeadWord := IR.Nodes[1].WordIndex;
  Candidate.LeftWord := IR.Nodes[2].WordIndex;
  Candidate.RightWord := IR.Nodes[3].WordIndex;
  Operation := Candidate; { публікація лише після повного допуску }
end;

{ Приватний емітер. Після LowerPinnedD3Eq тут НІ reader, НІ binder,
  НІ виклику nativeeval. Обидва D1 — лише машинні immediate-операнди;
  результат 0/1 обчислюють CMP/SETE при справжньому виконанні ELF. }
function EmitLoweredEq(const Op: TLoweredD3Eq): RawByteString;
var
  Machine: RawByteString;
  Total, I: SizeInt;
  procedure PutLE(Offset: SizeInt; V: QWord; Count: SizeInt);
  var J: SizeInt;
  begin
    if (Offset < 0) or (Count < 1) or (Count > 8) or
       (Offset > Length(Result)-Count) then
      raise EEqIRError.Create('Поле ELF64 вийшло за межі образу');
    for J := 0 to Count-1 do begin
      Result[Offset+J+1] := AnsiChar(Byte(V and $FF));
      V := V shr 8;
    end;
  end;
begin
  Result := '';
  Require((Op.LeftBit <= 1) and (Op.RightBit <= 1),
    'Операнд D1 вийшов за двійкову межу');
  Machine :=
    #$B8 + AnsiChar(Op.LeftBit) + #0#0#0 +
    #$B9 + AnsiChar(Op.RightBit) + #0#0#0 +
    #$39#$C8 + #$0F#$94#$C0 + #$0F#$B6#$C0 +
    #$04#$30 + #$48#$83#$EC#$08 +
    #$88#$04#$24 + #$C6#$44#$24#$01#$0A +
    #$B8#$01#0#0#0 + #$BF#$01#0#0#0 +
    #$48#$89#$E6 + #$BA#$02#0#0#0 +
    #$0F#$05 + #$B8#$3C#0#0#0 + #$31#$FF + #$0F#$05;
  Require(Length(Machine) = 61,
    'Несподівана довжина підтвердженого x86-64 EQ-шаблону');
  Total := HeaderBytes + Length(Machine);
  SetLength(Result, Total);
  FillChar(Result[1], Total, 0);
  PutLE(0, $464C457F, 4);
  PutLE(4, 2, 1); PutLE(5, 1, 1); PutLE(6, 1, 1);
  PutLE(16, 2, 2); PutLE(18, 62, 2); PutLE(20, 1, 4);
  PutLE(24, ELFBase+HeaderBytes, 8); PutLE(32, 64, 8);
  PutLE(52, 64, 2); PutLE(54, 56, 2); PutLE(56, 1, 2);
  PutLE(64, 1, 4); PutLE(68, 5, 4);
  PutLE(80, ELFBase, 8); PutLE(88, ELFBase, 8);
  PutLE(96, Total, 8); PutLE(104, Total, 8); PutLE(112, $1000, 8);
  for I := 1 to Length(Machine) do Result[HeaderBytes+I] := Machine[I];
end;

function BuildPinnedD3EqIRELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;
var
  Lowered: TLoweredD3Eq;
  Geometry: TELFGeometry;
begin
  Result := '';
  try
    LowerPinnedD3Eq(Physical, AuthorityRoot, Lowered);
    Result := EmitLoweredEq(Lowered);
    VerifySENSELF64(Result, Geometry);
    Require((Geometry.Kind = 2) and
            (Geometry.FileBytes = Length(Result)),
      'Породжений машинний образ не пройшов незалежну ELF64-геометрію');
  except
    Result := '';
    raise;
  end;
end;

{ Типи/час життя: Physical — незмінні packed T5M bytes; IR та Tables —
  локальні керовані FPC масиви, які звільняє scope. Lowered — три фізичні
  word-index і два D1-біти, не SENS-об'єкт. Result — окремий ELF64 blob,
  ніколи не канонічний .sens; на помилці не публікується.
  Питання: 1) Чому ExactIR guard не дає права виклику?
  2) Чому D7 не можна прийняти замість D1, навіть якщо байти схожі?
  3) Чому машинний результат обчислює SETE, а не Pascal?
  4) Чому емітеру більше не потрібні Physical/AuthorityRoot?
  5) Чому D12+ не приводиться до host Byte? }
end.
