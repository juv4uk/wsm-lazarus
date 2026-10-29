{ G6.97 — CLI: зібрати нативний `fib` із ТІЛА SENS (не host-код).
  Аргументи: <repo-root> <n> <out-path>
  Тіло будується як точні слова (проєкція в дані), знижується
  wsm.lowerd24 і записується ELF64 ET_EXEC. Це той самий шлях, що й у
  тесті зниження, але доступний близнюкам для порівняння. }
program sensfiblower;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d7text, wsm.lowerd24;

var
  Map: TD7Map;

function NameBits(const Text: String): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  DecodeT5M(EncodeD7Text(RawByteString(Text), Map, dsUk), Words);
  Result := '';
  for I := 0 to High(Words) do Result := Result + Words[I];
end;

function NameNode(const Bits: RawByteString): TExactWords;
var
  I, P: SizeInt;
begin
  SetLength(Result, (Length(Bits) div 7) + 2);
  Result[0] := '10';
  P := 1; I := 1;
  while I + 6 <= Length(Bits) do begin
    Result[P] := Copy(Bits, I, 7); Inc(P); Inc(I, 7);
  end;
  Result[P] := '01';
  SetLength(Result, P + 1);
end;

function D24(Value: LongWord): RawByteString;
var
  Bits: String;
  I: SizeInt;
begin
  SetLength(Bits, 24);
  for I := 1 to 24 do
    if (Value and (LongWord(1) shl (24 - I))) <> 0 then Bits[I] := '1'
    else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

function Concat(const Parts: array of TExactWords): TExactWords;
var
  I, K, P: SizeInt;
begin
  SetLength(Result, 0);
  P := 0;
  for I := 0 to High(Parts) do
    for K := 0 to High(Parts[I]) do begin
      SetLength(Result, P + 1);
      Result[P] := Parts[I][K];
      Inc(P);
    end;
end;

function One(const Word: RawByteString): TExactWords;
begin
  SetLength(Result, 1);
  Result[0] := Word;
end;

function QuoteAtom(const Word: RawByteString): TExactWords;
begin
  SetLength(Result, 4);
  Result[0] := '10'; Result[1] := '001'; Result[2] := Word; Result[3] := '01';
end;

function Clause(const Test, Body: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), Test, Body, One('01')]);
end;

function Call1(const NameNode, Arg: TExactWords): TExactWords;
begin
  Result := Concat([One('10'), NameNode, Arg, One('01')]);
end;

var
  ParamBits, SelfBits: RawByteString;
  ParamRef, SelfNode, Body, Image: TExactWords;
  N: LongWord;
  Stream: TFileStream;
  Raw: RawByteString;
begin
  if ParamCount < 3 then begin
    Writeln(StdErr, 'вжиток: sensfiblower <repo-root> <n> <out-path>');
    Halt(2);
  end;
  LoadPinnedD7Map(ParamStr(1), Map);
  N := LongWord(StrToInt64(ParamStr(2)));

  ParamBits := NameBits('величина');
  SelfBits := NameBits('фіб-сенс');
  ParamRef := NameNode(ParamBits);
  SelfNode := NameNode(SelfBits);

  { (за-умовою ((менше? величина 2) величина)
               (так (додати (фіб-сенс (відняти величина 1))
                            (фіб-сенс (відняти величина 2))))) }
  Body := Concat([One('10'), One('110'),
    Clause(Concat([One('10'), One('11010'), ParamRef, QuoteAtom(D24(2)), One('01')]),
           ParamRef),
    Clause(One('1'),
      Concat([One('10'), One('01010'),
        Call1(SelfNode, Concat([One('10'), One('01011'), ParamRef,
          QuoteAtom(D24(1)), One('01')])),
        Call1(SelfNode, Concat([One('10'), One('01011'), ParamRef,
          QuoteAtom(D24(2)), One('01')])),
        One('01')])),
    One('01')]);

  Raw := LowerBodyWithSelfELF(EncodeT5M(Body), EncodeT5M(NameNode(ParamBits)),
    EncodeT5M(One(D24(N))), EncodeT5M(NameNode(SelfBits)));

  Stream := TFileStream.Create(ParamStr(3), fmCreate);
  try
    if Length(Raw) > 0 then Stream.WriteBuffer(Raw[1], Length(Raw));
  finally
    Stream.Free;
  end;
end.
