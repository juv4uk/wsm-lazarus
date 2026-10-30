{ S0/T5M: фізична SENS .sens -> українська «укр» проєкція.
  Жодної історичної семантики McCarthy / SID8: лише чинні pinned
  T5M, D2 і шість колонок SENS. Повторне кодування тексту не заявлено.

  Вхід: один файл <= 65536 байтів packed T5M, pinned ROOT.
  TD2Document володіє деревом до finally; рядки RawByteString — managed.
  Результат: один UTF-8 рядок/корінь, лише після повної перевірки.
  Питання: чому NIL S0 не тотожний D3:000? Чому немає таблиці
  QUOTE->001? Чому невідомий W24 відхиляємо? Хто володіє AST?
  Чому stdout не пишеться до завершення перевірок? }
program senst5mukr;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.domain, wsm.proektsii;

const
  MaxInputBytes = 65536;
  MaxOutputBytes = 262144;
  MaxRenderDepth = 128;

type
  EBridgeError = class(Exception);

function ReadPhysical(const Path: String): RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path)) <> '.sens' then
    raise EBridgeError.Create('очікується фізичний .sens, не текстовий дамп');
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size < 1) or (F.Size > MaxInputBytes) then
      raise EBridgeError.Create('фізичний файл поза межею 1..65536 байтів');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

procedure AppendBounded(var Destination:RawByteString; const Value:RawByteString);
begin
  if Length(Value)>MaxOutputBytes-Length(Destination) then
    raise EBridgeError.Create('надмірно велика проєкція');
  Destination := Destination + Value;
end;

{ Каталог позичено з pinned LoadPinnedProjections. Не зберігаємо
  жодних історичних Name->Bits або власної таблиці значень.
  W7 показує окрему текстову координату, НЕ утворює автоматично
  ідентифікатор. W12+ потребує окремого числового закону. }
function ProjectAtom(const Bits:RawByteString;
  const Catalog:TProektsiiCatalog):RawByteString;
var W:SizeInt; Key:TDomainKey; Row:TProektsiiaRow;
begin
  W := Length(Bits);
  if (W<1) or (W>10) or (W=2) then
    raise EBridgeError.Create('немає безпечної укр-проєкції W'+IntToStr(W));
  Key := ExactKey(Bits);
  if (Key.Bits>=Length(Catalog[W])) or
     (not SameKey(Key,Catalog[W][Key.Bits].Key)) then
    raise EBridgeError.Create('відсутня pinned точна координата');
  Row := Catalog[W][Key.Bits];
  Result := Row.Surface[1]; { укр, не ук і не історична LISP }
  if (Result='') or (Result='()') then
    raise EBridgeError.Create('для координати немає укр-проєкції');
end;

procedure RenderNode(const Node:TD2Node; const Catalog:TProektsiiCatalog;
  Depth:SizeInt; var Text:RawByteString);
var I:SizeInt;
begin
  if (Node=nil) or (Depth>MaxRenderDepth) then
    raise EBridgeError.Create('надмірна глибина/порожній вузол');
  case Node.Kind of
    dkEmpty:
      AppendBounded(Text,'()'); { це D3:000, НЕ D1:0 }
    dkIdentity:
      AppendBounded(Text,ProjectAtom(Node.Bits,Catalog));
    dkList: begin
      AppendBounded(Text,'(');
      for I:=0 to High(Node.Children) do begin
        if I<>0 then AppendBounded(Text,' ');
        RenderNode(Node.Children[I],Catalog,Depth+1,Text);
      end;
      AppendBounded(Text,')');
    end;
    dkPair: begin
      if Length(Node.Children)<>2 then
        raise EBridgeError.Create('пошкоджена D2 пара');
      AppendBounded(Text,'(');
      RenderNode(Node.Children[0],Catalog,Depth+1,Text);
      AppendBounded(Text,' . ');
      RenderNode(Node.Children[1],Catalog,Depth+1,Text);
      AppendBounded(Text,')');
    end;
  else
    raise EBridgeError.Create('невідомий вузол D2');
  end;
end;

procedure WriteRaw(const S:RawByteString);
var Stream:THandleStream;
begin
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try
    if S<>'' then Stream.WriteBuffer(S[1],Length(S));
  finally
    Stream.Free;
  end;
end;

var
  Catalog:TProektsiiCatalog;
  Doc:TD2Document;
  Words:TExactWords;
  Physical, ResultText:RawByteString;
  I:SizeInt;
begin
  Doc:=nil;
  try
    if ParamCount<>2 then
      raise EBridgeError.Create('використання: senst5mukr ROOT програма.sens');
    Physical:=ReadPhysical(ParamStr(2));
    DecodeT5M(Physical,Words);
    Doc:=ParseD2WordsWide(Words);
    LoadPinnedProjections(ParamStr(1),Catalog);
    ResultText:='';
    for I:=0 to High(Doc.Roots) do begin
      RenderNode(Doc.Roots[I],Catalog,0,ResultText);
      AppendBounded(ResultText,#10);
    end;
    if ResultText='' then
      raise EBridgeError.Create('порожній D2 документ');
    WriteRaw(ResultText); { лише після атомарного допуску }
  except
    on E:Exception do begin
      WriteLn(StdErr,'S0-T5M-УКР-БЛОК: ',E.Message);
      ExitCode:=2;
    end;
  end;
  Doc.Free;
end.
