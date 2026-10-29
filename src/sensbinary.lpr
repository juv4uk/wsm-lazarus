{ G2.8: фізична діагностика двійкового зв'язування без надання викличності.
  Єдина семантична влада — pinned SENS, а не цей Pascal CLI. }
program sensbinary;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.domain,
  wsm.bind, wsm.binarybind, wsm.binarytree, wsm.proektsii;

type
  EBinaryCLIError = class(Exception);

function ReadPhysical(const FileName: String): RawByteString;
var F: TFileStream;
begin
  if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
    raise EBinaryCLIError.Create('очікується фізичний файл .sens, не проєкція .lisp');
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
      raise EBinaryCLIError.Create('порожній або завеликий фізичний файл');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

{ Явний перемикач D10 — механізм host CLI, НЕ inference домену або
  викличності. Старий --аналіз використовує незмінний W1..W9 binder. }
procedure Analyze(const FileName: String; AllowD10: Boolean);
var
  Physical: RawByteString;
  Tables: TDomainSet;
  Bound: TBinaryWords;
  I: SizeInt;
  EmptyLabel, Surface: RawByteString;
begin
  Physical := ReadPhysical(FileName);
  { Ні українське написання, ні історичний SID8 не визначають координату. }
  LoadPinnedDomains('external/sens', Tables);
  if AllowD10 then
    BindT5MBinaryD10(Physical, Tables, Bound)
  else
    BindT5MBinary(Physical, Tables, Bound);
  { Весь T5M, D2 та доменний ввід перевірено до першого байта stdout. }
  for I := 0 to High(Bound) do begin
    if Bound[I].IsEmpty then EmptyLabel := 'так' else EmptyLabel := 'ні';
    Surface := Bound[I].Ukrainian;
    if Surface = '' then Surface := 'немає';
    WriteLn('ДВІЙКОВЕ-СЛОВО індекс=', Bound[I].WordIndex,
      ' форма=', Bound[I].RootIndex, ' домен=', Bound[I].Key.Width,
      ' біти=', KeyBits(Bound[I].Key), ' порожнє=', EmptyLabel,
      ' ук=', Surface);
  end;
  WriteLn('ДВІЙКОВЕ-ПІДСУМОК слів=', Length(Bound),
    ' викличність=не-перевірено виконання=не-перевірено');
end;


{ G2.37: огляд того САМОГО фізичного D2-дерева, що вже бачить Lazarus.
  Вхід Physical: borrowed packed канонічний T5M, Tables/Catalog: pinned.
  Entry: borrowed host-record ReadBinaryTree (не SENS значення).
  Похідна dkPair має лише опору, НЕ вигадану фізичну адресу.
  Вивід staged TMemoryStream — нуль stdout до перевірки всіх вузлів;
  усі керовані масиви й тимчасовий буфер звільняються після виклику. }
procedure InspectPhysicalTree(const FileName: String; AllowD10: Boolean);
const
  MaxViewNodes = 4096;
  MaxViewBytes = 4 * 1024 * 1024;
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
var
  Physical, Line, Surface: RawByteString;
  Tables: TDomainSet;
  Catalog: TProektsiiCatalog;
  Tree: TBinaryTreeEntries;
  Entry: TBinaryTreeEntry;
  Row: TProektsiiaRow;
  Report: TMemoryStream;
  OutputStream: THandleStream;
  I, J: SizeInt;

  procedure AddLine(const Value: RawByteString);
  var S: RawByteString;
  begin
    S := Value + #10;
    if (Length(S) > MaxViewBytes) or
       (Report.Size > MaxViewBytes - Length(S)) then
      raise EBinaryCLIError.Create('перевищено межу 4 МіБ звіту дерева');
    Report.WriteBuffer(S[1], Length(S));
  end;

begin
  Physical := ReadPhysical(FileName);
  LoadPinnedDomains('external/sens', Tables);
  LoadPinnedProjections('external/sens', Catalog);
  { D10 дозволено тільки явною host-командою. Обидва режими
    використовують той самий фізичний reader, pinned binder та D2-дерево. }
  if AllowD10 then
    ReadBinaryTreeD10(Physical, Tables, Tree)
  else
    ReadBinaryTree(Physical, Tables, Tree);
  if Length(Tree) > MaxViewNodes then
    raise EBinaryCLIError.Create('понад 4096 вузлів фізичного дерева');
  Report := TMemoryStream.Create;
  try
    for I := 0 to High(Tree) do begin
      Entry := Tree[I];
      Line := 'ДЕРЕВО-ВУЗОЛ номер=' + IntToStr(I) +
        ' форма=' + IntToStr(Entry.RootIndex) +
        ' батько=' + IntToStr(Entry.ParentIndex) +
        ' дитина=' + IntToStr(Entry.ChildIndex) +
        ' глибина=' + IntToStr(Entry.Depth);
      case Entry.Kind of
        dkList: Line := Line + ' вид=список-D2';
        dkPair: Line := Line + ' вид=похідна-пара';
        dkIdentity: Line := Line + ' вид=точне-слово';
        dkEmpty: Line := Line + ' вид=порожнє-D3:000';
        else raise EBinaryCLIError.Create('невідомий тип D2 вузла');
      end;
      if not Entry.HasPhysicalWord then begin
        if (Entry.Kind <> dkPair) or (Entry.Key.Width <> 0) then
          raise EBinaryCLIError.Create('синтетичний вузол має чужий тип або домен');
        Line := Line + ' фізичне=ні опора=' + IntToStr(Entry.AnchorWordIndex) +
          ' координата=немає';
      end else begin
        if (Entry.Kind = dkPair) or Entry.Physical.IsEOF or
           (Entry.Physical.WordIndex <> Entry.AnchorWordIndex) or
           (Entry.Physical.TritEnd <= Entry.Physical.TritStart) or
           (Entry.Physical.ByteEnd <= Entry.Physical.ByteStart) then
          raise EBinaryCLIError.Create('некоректна фізична адреса дерева');
        Line := Line + ' фізичне=так слово=' + IntToStr(Entry.Physical.WordIndex) +
          ' трити=[' + IntToStr(Entry.Physical.TritStart) + ',' +
          IntToStr(Entry.Physical.TritEnd) + ')' +
          ' байти=[' + IntToStr(Entry.Physical.ByteStart) + ',' +
          IntToStr(Entry.Physical.ByteEnd) + ')';
      end;
      if Entry.Kind in [dkIdentity, dkEmpty] then begin
        if (Entry.Key.Width < 1) or (Entry.Key.Width > (9 + Ord(AllowD10))) or
           (Entry.Key.Bits >= QWord(Length(Catalog[Entry.Key.Width]))) then
          raise EBinaryCLIError.Create('листок поза pinned D1–D' +
            IntToStr(9 + Ord(AllowD10)));
        Row := Catalog[Entry.Key.Width][Entry.Key.Bits];
        if not SameKey(Row.Key, Entry.Key) then
          raise EBinaryCLIError.Create('не збіглася exact-domain координата');
        if (Entry.Kind = dkEmpty) <> (KeyBits(Entry.Key) = '000') then
          raise EBinaryCLIError.Create('D3:000 не є D1:0');
        Line := Line + ' домен=D' + IntToStr(Entry.Key.Width) +
          ' біти=' + KeyBits(Entry.Key);
        for J := 0 to 5 do begin
          Surface := Row.Surface[J]; { pinned проєкції, ніколи dispatch }
          if Surface = '' then Surface := '()';
          Line := Line + ' ' + Labels[J] + '=' + Surface;
        end;
      end else begin
        if Entry.Key.Width <> 0 then
          raise EBinaryCLIError.Create('структурний вузол має вигаданий домен');
        Line := Line + ' домен=немає проєкції=немає';
      end;
      AddLine(Line);
    end;
    AddLine('ДЕРЕВО-ПІДСУМОК вузлів=' + IntToStr(Length(Tree)) +
      ' викличність=не-перевірено виконання=не-перевірено');
    { Публікація тільки після всього pinned, T5M, D2, exact-key admission.
      Якщо downstream pipe зникає під час Write, ОС не гарантує атомарності. }
    OutputStream := THandleStream.Create(TextRec(Output).Handle);
    try
      Report.Position := 0;
      OutputStream.CopyFrom(Report, Report.Size);
    finally OutputStream.Free end;
  finally
    Report.Free;
  end;
end;

begin
  if (ParamCount <> 2) or
     ((ParamStr(1) <> '--аналіз') and (ParamStr(1) <> '--дерево') and
      (ParamStr(1) <> '--аналіз-д10') and
      (ParamStr(1) <> '--дерево-д10')) then begin
    WriteLn(StdErr, 'ВИКОРИСТАННЯ: sensbinary --аналіз|--аналіз-д10|--дерево|--дерево-д10 файл.sens');
    Halt(64);
  end;
  try
    if (ParamStr(1) = '--дерево') or
       (ParamStr(1) = '--дерево-д10') then
      InspectPhysicalTree(ParamStr(2), ParamStr(1) = '--дерево-д10')
    else
      Analyze(ParamStr(2),ParamStr(1)='--аналіз-д10');
  except
    on E: ED2SourceError do begin
      WriteLn(StdErr, 'ДВІЙКОВЕ-ПОМИЛКА слово=', E.WordIndex, ': ', E.Message);
      Halt(1);
    end;
    on E: Exception do begin
      WriteLn(StdErr, 'ДВІЙКОВЕ-ПОМИЛКА ', E.Message);
      Halt(1);
    end;
  end;
end.
