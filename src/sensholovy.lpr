{ G2.13. Українська діагностика синтаксичних голів із канонічного .sens.
  Єдине джерело координат: pinned SENS через готові T5M/D2/tree/heads.
  Звичайний український .lisp — ОКРЕМА людська проєкція, не цей файл.
  Виділена синтаксична голова не є семантичним дозволом виклику. }
program sensholovy;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarytree, wsm.binaryheads;

const MaxViewHeads = 20000;
type EHolovyInput = class(Exception);
var ErrorText: String; ExitCode: Integer;

function ReadPhysical(const FileName: String): RawByteString;
var Stream: TFileStream;
begin
  if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
    raise EHolovyInput.Create('очікується фізичний .sens; .lisp є українською текстовою проєкцією');
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size <= 0) or (Stream.Size > MAX_T5M_FILE_BYTES) then
      raise EHolovyInput.Create('порожній або завеликий фізичний .sens');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally Stream.Free; end;
end;

function KindName(const Kind: TBinaryHeadKind): String;
begin
  case Kind of
    hkNoHead: Result := 'без-голови';
    hkExactHead: Result := 'точна';
    hkStructuralHead: Result := 'структурна';
    else raise EHolovyInput.Create('невідомий стан синтаксичної голови');
  end;
end;

function SpanText(const S: TPhysicalWordSpan): String;
begin
  if S.IsEOF then raise EHolovyInput.Create('голова має фізичну адресу EOF');
  Result := ' слово=' + IntToStr(S.WordIndex) +
    ' трити=[' + IntToStr(S.TritStart) + ',' + IntToStr(S.TritEnd) + ')' +
    ' байти=[' + IntToStr(S.ByteStart) + ',' + IntToStr(S.ByteEnd) + ')';
end;

procedure Run(const FileName, AuthorityRoot: String);
var Physical: RawByteString;
    Tables: TDomainSet;
    Tree: TBinaryTreeEntries;
    Heads: TBinaryHeads;
    Lines: TStringList;
    I, ExactCount, StructuralCount, EmptyCount: SizeInt;
    H: TBinaryHead;
    Entry: TBinaryTreeEntry;
    Line: String;
begin
  Physical := ReadPhysical(FileName);
  LoadPinnedDomains(RawByteString(AuthorityRoot), Tables);
  ReadBinaryTree(Physical, Tables, Tree);
  CollectBinaryHeads(Tree, Heads);
  if Length(Heads)>MaxViewHeads then
    raise EHolovyInput.Create('перевищено ліміт діагностичного перегляду');
  Lines := TStringList.Create;
  try
    ExactCount := 0; StructuralCount := 0; EmptyCount := 0;
    for I := 0 to High(Heads) do begin
      H := Heads[I];
      Line := 'ГОЛОВА список=' + IntToStr(H.ListIndex) +
        ' форма=' + IntToStr(H.RootIndex) +
        ' вид=' + KindName(H.Kind) +
        ' перший-вузол=' + IntToStr(H.HeadIndex);
      case H.Kind of
        hkNoHead: Inc(EmptyCount);
        hkExactHead: begin
          Inc(ExactCount);
          if (H.HeadIndex < 0) or (H.HeadIndex >= Length(Tree)) then
            raise EHolovyInput.Create('індекс голови поза деревом');
          Entry := Tree[H.HeadIndex];
          if (Entry.Kind <> dkIdentity) or
             not SameKey(Entry.Key, H.Key) or
             (H.WordIndex <> Entry.AnchorWordIndex) then
            raise EHolovyInput.Create('голова втратила точну фізичну тотожність');
          Line := Line + ' домен=' + IntToStr(H.Key.Width) +
            ' біти=' + String(KeyBits(H.Key)) +
            SpanText(H.Physical);
          if Entry.Ukrainian <> '' then
            Line := Line + ' ук=' + String(Entry.Ukrainian);
        end;
        hkStructuralHead: begin
          Inc(StructuralCount);
          if (H.HeadIndex < 0) or (H.HeadIndex >= Length(Tree)) then
            raise EHolovyInput.Create('структурний вузол поза деревом');
          Entry := Tree[H.HeadIndex];
          case Entry.Kind of
            dkList: Line := Line + ' структура=список-D2';
            dkPair: Line := Line + ' структура=похідна-пара';
            dkEmpty: Line := Line + ' структура=порожня-D3:000';
            else raise EHolovyInput.Create('атом помилково позначено структурним');
          end;
          if Entry.HasPhysicalWord then
            Line := Line + SpanText(Entry.Physical)
          else
            Line := Line + ' фізичне-слово=відсутнє';
        end;
      end;
      Lines.Add(Line);
    end;
    Lines.Add('ПІДСУМОК списків=' + IntToStr(Length(Heads)) +
      ' точних=' + IntToStr(ExactCount) +
      ' структурних=' + IntToStr(StructuralCount) +
      ' порожніх=' + IntToStr(EmptyCount) +
      ' викличність=не-доведено');
    { Не друкуємо частковий реєстр при помилці T5M/D2/binder/формату. }
    Write(Lines.Text);
  finally Lines.Free; end;
end;

begin
  ErrorText := ''; ExitCode := 1;
  try
    if (ParamCount <> 3) or (ParamStr(1) <> '--голови') then begin
      ExitCode := 64;
      raise EHolovyInput.Create('використання: sensholovy --голови файл.sens pinned-sens-root');
    end;
    Run(ParamStr(2), ParamStr(3));
  except
    on E: ED2PhysicalError do
      ErrorText := 'D2 слово=' + IntToStr(E.Span.WordIndex) +
        ' трити=[' + IntToStr(E.Span.TritStart) + ',' +
        IntToStr(E.Span.TritEnd) + ') байти=[' +
        IntToStr(E.Span.ByteStart) + ',' +
        IntToStr(E.Span.ByteEnd) + '): ' + E.Message;
    on E: Exception do ErrorText := E.Message;
  end;
  if ErrorText <> '' then begin
    WriteLn(StdErr, 'ДВІЙКОВІ-ГОЛОВИ-ПОМИЛКА: ', ErrorText);
    Halt(ExitCode);
  end;
end.
