{ G6.146 — два різні pinned source-backed Core1 DEFINE з D5:01010,
  D5:01011 як ДВІ ОКРЕМІ справжні x86-64 функції: EDI/ESI -> EAX.
  Програма G6.141, що вже пройшла оригінальний Core1 binary census,
  D4 DEFINE/LAMBDA, D7 identity, pinned D5, numeric D12 gates і
  verified native ELF, є ЄДИНИМ входом для цього вузького postpass.
  НЕ новий мовний law/evaluator/emitter: host MOV/ALU береться з
  wsm.x64code/x64alu, CALL/RET/fixups із wsm.x64call.
  Тільки старий 15-байтовий точно перевірений префікс замінюється
  на 27-байтовий префікс з двома CALL; хвостовий T5M writer і таблиці
  переміщуються разом, їхні RIP-rel displacement не змінюються.
  Два окремі 5-байтові функціональні блоки розташовані ПІСЛЯ
  sys_exit та фізичних таблиць; самі входи відомі тільки CALL fixups.

  Вхід A/B/C — borrowed canonical T5M packed D12, RepoRoot — borrowed
  pinned робоче дерево; Original/Code/Result — власні FPC managed
  байти; у разі відмови Result порожній, жоден ELF не публікується.
  RSP від _start вирівняний до 16 перед кожним CALL, після RET
  залишається незмінним. 32-bit EDI/ESI/EAX тільки host ABI, не Dn.
  1) Чому два точні D7-ключі не визначаються текстовою проєкцією?
  2) Хто перевіряє проміжне signed D12 переповнення?
  3) Чому зберігається RIP-relative відстань writer->T5M таблиці?
  4) Як два незалежні CALL/RET відрізняються від inline G6.141?
  5) Чому додавання машинних підпрограм не означає повного APPLY? }
unit wsm.core1twocallabi;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ECore1TwoCallABIError=class(Exception);
function BuildPinnedCore1TwoCallABIELF(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
implementation
uses wsm.lowercore1twocalls,wsm.elfgeometry,
  wsm.x64code,wsm.x64alu,wsm.x64call;

const
  HeaderBytes=120;
  OldPrefixBytes=15; { B8 A; 05 B; 2D C }
  NewPrefixBytes=27; { BF A; BE B; CALL; 89 C7; BE C; CALL }
  FunctionBytes=5; { 89 F8; 01/29 F0; C3 }
  MaxABIImageBytes=HeaderBytes+256;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise ECore1TwoCallABIError.Create(Why);
end;

{ Offset is zero-based byte offset into ELF, never a SENS bit or
  domain index. Read-only: no partial-state mutation on malformed ELF. }
function ReadLE32(const Bytes:RawByteString;Offset:SizeInt):LongWord;
var K:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Bytes)-4),
    'некоректний host immediate у вихідному ELF');
  Result:=0;
  for K:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Bytes[Offset+K+1]));
end;

procedure PutLE64(var Bytes:RawByteString;Offset:SizeInt;Value:QWord);
var K:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Bytes)-8),
    'новий розмір виходить за фізичну межу ELF');
  for K:=0 to 7 do begin
    Bytes[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Result — owned ELF64 PIE generated only from the already verified
  original compiler. No host arithmetic of a SENS value is performed:
  each CALL uses the existing host ALU emitter at execution time. }
function BuildPinnedCore1TwoCallABIELF(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
var
  Original,OldTail,NewMachine:RawByteString;
  Code:TX64Code;
  OldG,NewG:TELFGeometry;
  A,B,C:LongWord;
  CallAddDisp,CallSubDisp,AddAt,SubAt:SizeInt;
begin
  Result:='';
  Original:=BuildPinnedCore1TwoCallsELF(RepoRoot,
    APhysical,BPhysical,CPhysical);
  VerifySENSELF64(Original,OldG);
  Need((OldG.Kind=3) and (OldG.Entry=HeaderBytes) and
       (OldG.FileBytes=Length(Original)) and
       (Length(Original)>HeaderBytes+OldPrefixBytes+40) and
       (Length(Original)+NewPrefixBytes-OldPrefixBytes+
          2*FunctionBytes<=MaxABIImageBytes),
    'змінився профіль оригінального verified ELF64 PIE');
  Need((Original[HeaderBytes+1]=#$B8) and
       (Original[HeaderBytes+6]=#$05) and
       (Original[HeaderBytes+11]=#$2D) and
       (Original[HeaderBytes+16]=#$48) and
       (Original[HeaderBytes+17]=#$83) and
       (Original[HeaderBytes+18]=#$EC) and
       (Original[HeaderBytes+19]=#$08),
    'невідомий машинний MOV/ADD/SUB/T5M пролог; postpass заборонено');
  A:=ReadLE32(Original,HeaderBytes+1);
  B:=ReadLE32(Original,HeaderBytes+6);
  C:=ReadLE32(Original,HeaderBytes+11);
  OldTail:=Copy(Original,HeaderBytes+OldPrefixBytes+1,
    Length(Original)-HeaderBytes-OldPrefixBytes);
  Need(Length(OldTail)>40,'неповний T5M writer або таблиці');

  X64Reset(Code);
  X64MovImm32(Code,xrDI,A); { перший оригінальний source-backed D12 }
  X64MovImm32(Code,xrSI,B);
  X64EmitLocalCall(Code,CallAddDisp);
  { Перенести РЕАЛЬНИЙ результат CALL як перший аргумент іншої функції.
    89 C7: host MOV EDI,EAX; без Pascal обчислення SENS. }
  Need(Length(Code.Bytes)=15,'змінився ABI виклику додавання');
  Code.Bytes:=Code.Bytes+#$89#$C7;
  X64MovImm32(Code,xrSI,C);
  X64EmitLocalCall(Code,CallSubDisp);
  Need((Length(Code.Bytes)=NewPrefixBytes) and
       (CallAddDisp=11) and (CallSubDisp=23),
    'змінився точний префікс двох CALL');

  { Writer+T5M lookup переноситься НА ОДИН І ТОЙ САМИЙ offset,
    тому всі його внутрішні RIP displacement лишаються валідними. }
  Code.Bytes:=Code.Bytes+OldTail;
  AddAt:=Length(Code.Bytes);
  Code.Bytes:=Code.Bytes+#$89#$F8; { host MOV EAX,EDI }
  X64ALU32(Code,xaAdd,xrAX,xrSI);
  X64Return(Code);
  SubAt:=Length(Code.Bytes);
  Code.Bytes:=Code.Bytes+#$89#$F8;
  X64ALU32(Code,xaSub,xrAX,xrSI);
  X64Return(Code);
  Need((SubAt=AddAt+FunctionBytes) and
       (Length(Code.Bytes)=SubAt+FunctionBytes) and
       (Copy(Code.Bytes,AddAt+1,FunctionBytes)=#$89#$F8#$01#$F0#$C3) and
       (Copy(Code.Bytes,SubAt+1,FunctionBytes)=#$89#$F8#$29#$F0#$C3),
    'невірні два окремі 2-arg machine ALU/RET блоки');
  { Same-image rel32 after verified final layout. No relocation needed
    in PIE: CALL relative to RIP, not an absolute host address. }
  X64PatchLocalCall(Code,CallAddDisp,AddAt);
  X64PatchLocalCall(Code,CallSubDisp,SubAt);
  NewMachine:=X64Image(Code);
  Need(Length(NewMachine)=
      Length(Original)-HeaderBytes+
        NewPrefixBytes-OldPrefixBytes+2*FunctionBytes,
    'порушено точну байтову геометрію двох CALL');
  Result:=Copy(Original,1,HeaderBytes)+NewMachine;
  PutLE64(Result,96,QWord(Length(Result)));
  PutLE64(Result,104,QWord(Length(Result)));
  VerifySENSELF64(Result,NewG);
  Need((NewG.Kind=OldG.Kind) and
       (NewG.Entry=OldG.Entry) and
       (NewG.FileBytes=Length(Result)) and
       (NewG.MachineBytes=Length(NewMachine)),
    'новий ELF64 PIE із двома CALL не пройшов geometry guard');
end;
end.
