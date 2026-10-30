{ Core1.65: фізичний census D7-ідентичностей проти межі evaluator.
  Це перевірка повноти індексу, не запуск відхилених тіл і не семантичний oracle.
  Власні значення: Physical/Words/Document/Runtime звільняються у finally;
  Root, Name та їхні діти позичені від Document; Keys копіює лише D7-біти.
  Питання: чому D7-біти кращі за текстове ім’я тут? Хто володіє AST-вузлами?
  Чому відхилений ключ не означає помилкову семантику SENS? }
program TestCore1Census;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.core1selektor;

const
  ExpectedDefinitions = 96;
  ExpectedAdmitted = 94;
  ExpectedRejected = 2;
  MaxPhysicalBytes = 4 * 1024 * 1024;

type
  TKeys = array of RawByteString;

var
  RootPath, Filename: String;
  Physical: RawByteString;
  Words: TExactWords;
  Document: TD2Document;
  Runtime: TCore1Selektor;
  Keys: TKeys;
  I, J, Admitted, Rejected: SizeInt;

procedure Need(Condition: Boolean; const Why: String);
begin
  if not Condition then raise Exception.Create(Why);
end;

function ReadPhysical(const Path: String): RawByteString;
var
  Input: TFileStream;
begin
  Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    Need((Input.Size > 0) and (Input.Size <= MaxPhysicalBytes),
      'порожній або надмірний фізичний Core1');
    SetLength(Result, SizeInt(Input.Size));
    Input.ReadBuffer(Result[1], Length(Result));
  finally
    Input.Free;
  end;
end;

function ExactD7Key(const Node: TD2Node): RawByteString;
var
  Part: TD2Node;
  K: SizeInt;
begin
  Need((Node <> nil) and (Node.Kind = dkList) and
    (Length(Node.Children) > 0), 'ім’я визначення не є списком D7');
  Result := '';
  for K := 0 to High(Node.Children) do begin
    Part := Node.Children[K];
    Need((Part <> nil) and (Part.Kind = dkIdentity) and
      (Part.Width = 7) and (Length(Part.Bits) = 7),
      'D7-ключ містить не точне семибітне слово');
    Result := Result + Part.Bits;
  end;
end;

function FindKey(const Values: TKeys; const Needle: RawByteString): SizeInt;
var
  K: SizeInt;
begin
  for K := 0 to High(Values) do
    if Values[K] = Needle then Exit(K);
  Result := -1;
end;

procedure WriteUtf8Line(const Line: UnicodeString);
var
  Bytes: UTF8String;
  OutputStream: THandleStream;
begin
  Bytes := UTF8Encode(Line + #10);
  OutputStream := THandleStream.Create(TextRec(Output).Handle);
  try
    OutputStream.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    OutputStream.Free;
  end;
end;

procedure WriteRawLine(const Line: RawByteString);
var
  OutputStream: THandleStream;
  Bytes: RawByteString;
begin
  Bytes := Line + #10;
  OutputStream := THandleStream.Create(TextRec(ErrOutput).Handle);
  try
    OutputStream.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    OutputStream.Free;
  end;
end;

begin
  Document := nil;
  Runtime := nil;
  try
    try
      Need(ParamCount = 1, 'потрібен корінь робочого дерева');
      RootPath := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
      Filename := RootPath + 'external' + PathDelim + 'sens' + PathDelim +
        'lib' + PathDelim + 'core1.sens';

    { Physical — канонічні паковані байти; D2 дерево живе до завершення
      перевірки. Точні слова ніколи не перетворюються на десяткові числа. }
      Physical := ReadPhysical(Filename);
      DecodeT5M(Physical, Words);
      Need(EncodeT5M(Words) = Physical, 'T5M не проходить точний round-trip');
      Document := ParseD2WordsWide(Words);
      Need(Length(Document.Roots) = ExpectedDefinitions,
        'кількість фізичних визначень змінилася — оновіть свідому матрицю');

      SetLength(Keys, Length(Document.Roots));
      for I := 0 to High(Document.Roots) do begin
        Need((Document.Roots[I] <> nil) and
          (Document.Roots[I].Kind = dkList) and
          (Length(Document.Roots[I].Children) = 3) and
          (Document.Roots[I].Children[0] <> nil) and
          (Document.Roots[I].Children[0].Kind = dkIdentity) and
          (Document.Roots[I].Children[0].Width = 4) and
          (Document.Roots[I].Children[0].Bits = '0011'),
          'фізичний корінь не має форми pinned D4 DEFINE');
        Keys[I] := ExactD7Key(Document.Roots[I].Children[1]);
        Need(FindKey(Copy(Keys, 0, I), Keys[I]) < 0,
          'повторний точний D7 ключ у фізичному Core1');
      end;

    { Runtime сам завантажує той самий pinned core1.sens. Порівнюємо
      координати, не написання з .lisp і не припускаємо викличність. }
      Runtime := TCore1Selektor.Create(RootPath);
      Admitted := 0;
      Rejected := 0;
      for I := 0 to High(Keys) do begin
        J := Runtime.FindAdmitted(Keys[I]);
        if J >= 0 then Inc(Admitted)
        else begin
          Inc(Rejected);
          WriteUtf8Line('CORE1-CENSUS-НЕДОПУЩЕНО D7=' +
            UnicodeString(Keys[I]) + ' physical-root=' + UnicodeString(IntToStr(I + 1)));
        end;
      end;
      Need(Admitted = Runtime.AdmittedCount,
        'runtime містить ключ, відсутній у фізичному файлі');
      Need((Admitted = ExpectedAdmitted) and (Rejected = ExpectedRejected),
        'змінилася зафіксована межа допуску 94/96');
      WriteUtf8Line('CORE1-CENSUS-ГАРАЗД total=96 admitted=94 rejected=2 ' +
        'authority=physical-T5M identity=exact-D7 semantics=not-claimed');
  except
    on E: Exception do begin
      { Exception.Message already carries the source UTF-8 bytes. Write them
        raw: converting through UnicodeString would reinterpret FPC AnsiString
        under the process locale and corrupt a useful diagnostic. }
      WriteRawLine(RawByteString(UTF8Encode(UnicodeString(
        'CORE1-CENSUS-ПРОВАЛ: '))) + RawByteString(E.Message));
      ExitCode := 1;
    end;
    end;
  finally
    Runtime.Free;
    Document.Free;
  end;
end.
