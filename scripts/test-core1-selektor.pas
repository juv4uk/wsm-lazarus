{ Core1.6: живий FPC доказ другого й третього визначення сучасного Core1.
  Кожен виклик іде фізичним T5M; жодного текстового dispatch.
  Диференційний оракул для ПЕРШОГО визначення — уже злитий
  TCore1FirstRuntime: два незалежні шляхи мають дати ті самі байти. }
program TestCore1Selektor;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1selektor, wsm.core1first,
  wsm.core1index, wsm.core4runtime, wsm.binaryexec;

var
  Passed: SizeInt;
  Root: String;

procedure Check(Condition: Boolean; const Why: String);
begin
  Inc(Passed);
  if not Condition then raise Exception.Create('ПРОВАЛ: ' + Why);
end;

procedure WritePhysical(const Filename: String; const Physical: RawByteString);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(Filename, fmCreate);
  try
    if Length(Physical) > 0 then Stream.WriteBuffer(Physical[1], Length(Physical));
  finally
    Stream.Free;
  end;
end;

function El(const Bits: String): RawByteString;
begin
  Result := RawByteString(Bits);
end;

{ (10 (10 <D7 ім'я> 01) (10 1110 <елементи> 01) 01) — та сама фізична
  форма, яку вже використовує перший Core1-зріз. Це host-побудовник
  тестового входу, не reader і не interpreter. }
function MakeCall(const NameBits: RawByteString;
  const Elements: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I, P, Count: SizeInt;
begin
  Count := Length(NameBits) div 7;
  if (Count = 0) or (Count * 7 <> Length(NameBits)) then
    raise Exception.Create('недопустима довжина D7');
  SetLength(Words, Count + Length(Elements) + 9);
  P := 0;
  Words[P] := '10'; Inc(P);
  Words[P] := '10'; Inc(P);
  for I := 0 to Count - 1 do begin
    Words[P] := Copy(NameBits, I * 7 + 1, 7); Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := '10'; Inc(P);
  Words[P] := '1110'; Inc(P);
  for I := 0 to High(Elements) do begin
    Words[P] := Elements[I]; Inc(P);
  end;
  Words[P] := '01'; Inc(P);
  Words[P] := '01'; Inc(P);
  SetLength(Words, P);
  Result := EncodeT5M(Words);
end;

{ Незалежний оракул: D3:011 «решта» через TBinaryExecutor і
  D4:1001 «друге» через TCore4Runtime. Це ІНШИЙ шлях, ніж механізми юніта:
  ратифікована LISP-проєкція CADDR (lib/domains/d5.lisp) розкладає
  третій елемент саме як CADR(CDR x).
  Питання: чому це перевірка, а не другий закон? Чому аргумент цитовано?
  Хто звільняє тимчасові масиви слів? }
function CdrOnce(Bin: TBinaryExecutor;
  const Elements: array of RawByteString): TExactWords;
var
  Call, Quoted, List: TExactWords;
  Middle: RawByteString;
  I, N: SizeInt;
begin
  N := Length(Elements);
  { (10 011 (10 001 (10 <елементи> 01) 01) 01) }
  SetLength(List, N + 2);
  List[0] := '10';
  for I := 0 to N - 1 do List[I + 1] := Elements[I];
  List[High(List)] := '01';
  SetLength(Quoted, Length(List) + 3);
  Quoted[0] := '10'; Quoted[1] := '001';
  for I := 0 to High(List) do Quoted[I + 2] := List[I];
  Quoted[Length(List) + 2] := '01';
  SetLength(Call, Length(Quoted) + 3);
  Call[0] := '10'; Call[1] := '011';
  for I := 0 to High(Quoted) do Call[I + 2] := Quoted[I];
  Call[Length(Quoted) + 2] := '01';
  Middle := Bin.ExecutePhysicalT5M(EncodeT5M(Call));
  DecodeT5M(Middle, List);
  if (Length(List) < 2) or (List[0] <> '10') or
     (List[High(List)] <> '01') then
    raise Exception.Create('оракул D3:011 не повернув список');
  SetLength(Result, Length(List) - 2);
  for I := 1 to Length(List) - 2 do Result[I - 1] := List[I];
end;

function CadrOf(Exec: TCore4Runtime;
  const Elements: TExactWords): RawByteString;
var
  Call: TExactWords;
  I, N: SizeInt;
begin
  N := Length(Elements);
  { (10 1001 (10 1110 <елементи> 01) 01) }
  SetLength(Call, N + 6);
  Call[0] := '10'; Call[1] := '1001'; Call[2] := '10'; Call[3] := '1110';
  for I := 0 to N - 1 do Call[I + 4] := Elements[I];
  Call[N + 4] := '01'; Call[N + 5] := '01';
  Result := Exec.ExecutePhysicalCall(EncodeT5M(Call));
end;

function ComposedThird(Bin: TBinaryExecutor; Exec: TCore4Runtime;
  const Elements: array of RawByteString): RawByteString;
begin
  Result := CadrOf(Exec, CdrOnce(Bin, Elements));
end;

function ComposedCdrThird(Bin: TBinaryExecutor; Exec: TCore4Runtime;
  const Elements: array of RawByteString): RawByteString;
var
  Once: TExactWords;
begin
  Once := CdrOnce(Bin, Elements);
  Result := CadrOf(Exec, CdrOnce(Bin, Once));
end;

function ExpectRefusal(S: TCore1Selektor; const Physical: RawByteString;
  const Why: String): Boolean;
var
  Answer: RawByteString;
begin
  Answer := '';
  try
    Answer := S.ExecutePhysicalCall(Physical);
  except
    on E: Exception do begin
      Check(Answer = '', Why + ': відмова не має лишати часткової відповіді');
      Exit(True);
    end;
  end;
  Check(False, Why + ': очікувалася відмова, отримано ' + IntToStr(Length(Answer)) + ' байт');
  Result := False;
end;

var
  S: TCore1Selektor;
  First: TCore1FirstRuntime;
  Index: TCore1Index;
  A, B, C, D, Oracle: RawByteString;
  Bin: TBinaryExecutor;
  Exec: TCore4Runtime;
  Answer, ViaFirst: RawByteString;
  Bad, Name: RawByteString;
  OutDir: String;
  Words: TExactWords;
  Glyphs, I: SizeInt;
begin
  Passed := 0;
  Root := ParamStr(1);
  if Root = '' then raise Exception.Create('потрібен корінь робочого дерева');
  A := El('0000001'); B := El('0000010'); C := El('0000100'); D := El('0001000');
  S := TCore1Selektor.Create(Root);
  First := nil;
  Index := nil;
  Bin := TBinaryExecutor.Create(
    RawByteString(IncludeTrailingPathDelimiter(ExpandFileName(Root)) +
      'external' + PathDelim + 'sens'));
  Exec := TCore4Runtime.Create(Root);
  try
    { 1. Допущено щонайменше три визначення; порядок = порядок pinned коренів. }
    Check(S.AdmittedCount >= 3, 'допущено менше трьох визначень Core1');

    { 2. Тіла в точних pinned координатах — жодного вигаданого закону. }
    Check(S.AdmittedBodyText(0) = 'D4:1001', 'тіло 0 має бути D4:1001, є ' + S.AdmittedBodyText(0));
    Check(S.AdmittedBodyText(1) = 'D5:10011', 'тіло 1 має бути D5:10011, є ' + S.AdmittedBodyText(1));
    Check(S.AdmittedBodyText(2) = 'D5:10011(D3:011)', 'тіло 2 має бути D5:10011(D3:011), є ' + S.AdmittedBodyText(2));

    { 3. Механізми: рівно одна ратифікована координата на крок. }
    Check(S.AdmittedMechanismText(0) = 'D4:1001', 'механізми 0');
    Check(S.AdmittedMechanismText(1) = 'D5:10011', 'механізми 1');
    Check(S.AdmittedMechanismText(2) = 'D3:011,D5:10011', 'механізми 2');

    { 4. Точні D7-ключі збігаються з незалежним чинним індексом Core1. }
    Index := TCore1Index.Create(Root);
    Check(Index.Count = 96, 'pinned Core1 має 96 визначень, є ' + IntToStr(Index.Count));
    Check(Index.Definition(1).NameBits = S.AdmittedName(0), 'D7-ключ 0 розійшовся з індексом');
    Check(Index.Definition(2).NameBits = S.AdmittedName(1), 'D7-ключ 1 розійшовся з індексом');
    Check(Index.Definition(3).NameBits = S.AdmittedName(2), 'D7-ключ 2 розійшовся з індексом');

    { 5. ДРУГЕ визначення: друге з трьох. }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(0), [A, B, C]));
    Check(Answer = EncodeT5M([B]), 'друге з (a b c) має бути b');

    { 6. Диференційний оракул: той самий виклик через уже злитий
         TCore1FirstRuntime дає ті самі байти. }
    First := TCore1FirstRuntime.Create(
      IncludeTrailingPathDelimiter(ExpandFileName(Root)) + 'external' + PathDelim + 'sens',
      Root);
    ViaFirst := First.ExecutePhysicalCall(MakeCall(S.AdmittedName(0), [A, B, C]));
    Check(ViaFirst = Answer, 'перший зріз і новий зріз розійшлися на D4:1001');

    { 7. ДРУГЕ pinned визначення: третє з трьох (D5:10011). }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(1), [A, B, C]));
    Check(Answer = EncodeT5M([C]), 'третє з (a b c) має бути c');
    Check(Answer <> EncodeT5M([B]), 'третє не має дорівнювати другому');

    { 7b. Незалежний оракул: та сама координата через D3:011 + D4:1001
         дає ті самі байти, що й нативний D5:10011. }
    Oracle := ComposedThird(Bin, Exec, [A, B, C]);
    Check(Oracle = Answer, 'D5:10011 розійшовся з композицією CADR(CDR x)');

    { 8. ТРЕТЄ pinned визначення: третє від решти, тобто четверте. }
    Answer := S.ExecutePhysicalCall(MakeCall(S.AdmittedName(2), [A, B, C, D]));
    Check(Answer = EncodeT5M([D]), 'третє від решти (a b c d) має бути d');
    Oracle := ComposedCdrThird(Bin, Exec, [A, B, C, D]);
    Check(Oracle = EncodeT5M([D]), 'композиція не дала четвертого елемента');

    { 9. Відповідь є канонічним T5M: повторне кодування не змінює байтів. }
    DecodeT5M(Answer, Words);
    Check(EncodeT5M(Words) = Answer, 'відповідь не є канонічним T5M');

    { 10. Негативні: закороткий список — явна відмова, не порожнеча. }
    ExpectRefusal(S, MakeCall(S.AdmittedName(1), [A, B]), 'третє з двох елементів');
    ExpectRefusal(S, MakeCall(S.AdmittedName(1), [A]), 'третє з одного елемента');
    ExpectRefusal(S, MakeCall(S.AdmittedName(2), [A, B, C]), 'третє від решти трьох');

    { 11. Негатив: чужий D7-ключ не переадресовується на перше замикання. }
    ExpectRefusal(S, MakeCall(StringOfChar('1', 14), [A, B, C]), 'чужий D7-ключ');

    { 12. Негатив: аргумент не є D4:1110 списком (точний атом замість списку). }
    Name := S.AdmittedName(1);
    Glyphs := Length(Name) div 7;
    SetLength(Words, Glyphs + 5);
    Words[0] := '10';
    Words[1] := '10';
    for I := 0 to Glyphs - 1 do
      Words[I + 2] := Copy(Name, I * 7 + 1, 7);
    Words[Glyphs + 2] := '01';
    Words[Glyphs + 3] := '0000001';
    Words[Glyphs + 4] := '01';
    ExpectRefusal(S, EncodeT5M(Words), 'атомарний аргумент');

    { 13. Негатив: пошкоджений T5M не дає часткової відповіді. }
    Bad := MakeCall(S.AdmittedName(1), [A, B, C]);
    Bad := Copy(Bad, 1, Length(Bad) - 1) + #$FF;
    ExpectRefusal(S, Bad, 'пошкоджений T5M');

    { 14. Негатив: порожній вхід. }
    ExpectRefusal(S, '', 'порожній виклик');

    { Фізичні входи для CLI пишуться ТИМ САМИМ EncodeT5M: жодного
      другого кодера в тестовій обв'язці. }
    OutDir := ParamStr(2);
    if OutDir <> '' then begin
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-0.sens',
        MakeCall(S.AdmittedName(0), [A, B, C]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-1.sens',
        MakeCall(S.AdmittedName(1), [A, B, C]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-2.sens',
        MakeCall(S.AdmittedName(2), [A, B, C, D]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-short.sens',
        MakeCall(S.AdmittedName(1), [A, B]));
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-alien.sens',
        MakeCall(StringOfChar('1', 14), [A, B, C]));
      Bad := MakeCall(S.AdmittedName(1), [A, B, C]);
      Bad := Copy(Bad, 1, Length(Bad) - 1) + #$FF;
      WritePhysical(IncludeTrailingPathDelimiter(OutDir) + 'call-bad.sens', Bad);
    end;

    Writeln('CORE1-SELEKTOR-ГАРАЗД перевірок=', Passed);
    { Машинні маркери навмисно ASCII: їх звіряє shell незалежно від локалі. }
    Writeln('CORE1-SELEKTOR-PASS checks=', Passed);
    Writeln('CORE1-SELEKTOR-LIMIT=not-full-Core1-no-D12-arith-no-GC-no-REPL');
  finally
    Exec.Free;
    Bin.Free;
    Index.Free;
    First.Free;
    S.Free;
  end;
end.
