{ Core1.1 — доказ фізичного допуску першого визначення pinned Core1.
  Джерело законів: external/sens, жодної копії семантики у Pascal.
  Це не Core1 evaluator, compiler чи повний REPL. }
program senscore1dopus;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.source;

const
  MaxSourceBytes = 4 * 1024 * 1024;

type
  ECore1Admission = class(Exception);

{ У host-консолі FPC 3.2.2 WriteLn за замовчуванням може
  перетворювати українські літери на '?' через кодову сторінку.
  Передаємо лише UTF-8 байти, НЕ мовні SENS значення.
  Result: фізичний stdout/stderr без алокацій після виходу. }
procedure WriteUtf8Line(const Message:UnicodeString; ToError:Boolean);
var
  Raw:UTF8String;
  Stream:THandleStream;
begin
  Raw:=UTF8Encode(Message+#10);
  if ToError then
    Stream:=THandleStream.Create(TextRec(StdErr).Handle)
  else
    Stream:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(Raw)>0 then Stream.WriteBuffer(Raw[1],Length(Raw));
  finally
    Stream.Free;
  end;
end;

function ReadBounded(const Filename:String; MaxBytes:Int64):RawByteString;
var
  Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxBytes) then
      raise ECore1Admission.Create('порожній або надмірний pinned Core1 файл');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

procedure Demand(Ok:Boolean; const Reason:String);
begin
  if not Ok then raise ECore1Admission.Create(Reason);
end;

function IsD7Identifier(Node:TD2Node):Boolean;
var I:SizeInt;
begin
  Result:=(Node<>nil) and (Node.Kind=dkList) and
    (Length(Node.Children)>0) and (Length(Node.Children)<=256);
  if not Result then Exit;
  for I:=0 to High(Node.Children) do
    if (Node.Children[I]=nil) or
       (Node.Children[I].Kind<>dkIdentity) or
       (Node.Children[I].Width<>7) then Exit(False);
  Result:=True;
end;

procedure AdmitFirstCore1Definition(Root:TD2Node);
var Lambda,Params:TD2Node;
begin
  { Перевіряються лише вже pinned точні координати D4 і D7,
    без аналізу англійських/українських spelling для dispatch. }
  Demand((Root<>nil) and (Root.Kind=dkList) and
    (Length(Root.Children)=3),
    'перший корінь не є трипольовим фізичним визначенням');
  Demand((Root.Children[0]<>nil) and
    (Root.Children[0].Kind=dkIdentity) and
    (Root.Children[0].Width=4) and
    (Root.Children[0].Bits='0011'),
    'перший корінь не має pinned D4:0011');
  Demand(IsD7Identifier(Root.Children[1]),
    'ім’я першого визначення не є точною D7-послідовністю');
  Lambda:=Root.Children[2];
  Demand((Lambda<>nil) and (Lambda.Kind=dkList) and
    (Length(Lambda.Children)=3),
    'немає фізичного тіла першого замикання Core1');
  Demand((Lambda.Children[0]<>nil) and
    (Lambda.Children[0].Kind=dkIdentity) and
    (Lambda.Children[0].Width=4) and
    (Lambda.Children[0].Bits='0010'),
    'перше замикання не має pinned D4:0010');
  Params:=Lambda.Children[1];
  Demand((Params<>nil) and (Params.Kind=dkList) and
    (Length(Params.Children)=1) and
    IsD7Identifier(Params.Children[0]),
    'параметр першого замикання не має точної D7-форми');
  Demand(Lambda.Children[2]<>nil,
    'немає тіла першого визначення');
end;

{ Механічний host-перепис: усі фізичні байти T5M лишаються
  canonical. Документи живуть до finally; ніхто не позичає
  вузли AST після Free. Немає GC значень: GC integration окремо.
  Вихід — один український звіт лише ПІСЛЯ повного допуску.
  Питання: чому D4:0011 не є назвою? Чому потрібен D7?
  Хто звільняє AST? Чому 2 джерела не змішуються?
  Що відбувається при пошкодженні останнього T5M байта? }
procedure Admit(const RootPath:String);
var
  Prefix, Physical, Projection, Repacked:RawByteString;
  Doc:TD2Document;
  Src:TSourceDocument;
  Words:TExactWords;
  I:SizeInt;
begin
  Demand(RootPath<>'','відсутній корінь pinned репозиторію');
  Prefix:=IncludeTrailingPathDelimiter(ExpandFileName(RootPath))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim;
  Physical:=ReadBounded(String(Prefix)+'core1.sens',MAX_T5M_FILE_BYTES);
  Projection:=ReadBounded(String(Prefix)+'core1.lisp',MaxSourceBytes);
  Src:=nil; Doc:=nil;
  try
    { Незалежний повний структурний допуск обох представлень;
      лексична проєкція НЕ визначає закони, домени чи викличність. }
    Src:=ReadUkrainianSource(Projection);
    Demand(Length(Src.Forms)>0,'українська проєкція Core1 порожня');
    DecodeT5M(Physical,Words);
    Repacked:=EncodeT5M(Words);
    Demand(Repacked=Physical,'фізичний Core1 не канонічний T5M');
    Doc:=ParseD2WordsWide(Words);
    Demand(Length(Doc.Roots)>0,'фізичний Core1 не має D2-коренів');
    Demand(Length(Doc.Roots)=Length(Src.Forms),
      'кількість фізичних і українських Core1 форм не збігається');
    AdmitFirstCore1Definition(Doc.Roots[0]);
    { Жодна форма не повинна мати нульову фізичну довжину. }
    for I:=0 to High(Doc.Roots) do
      Demand((Doc.Roots[I]<>nil) and
        (Doc.Roots[I].WordIndex>=1) and
        (Doc.Roots[I].EndWordIndexExclusive>Doc.Roots[I].WordIndex),
        'пошкоджена фізична межа D2-кореня Core1');
    WriteUtf8Line('CORE1-ДОПУСК-ГАРАЗД форм-укр='+
      UnicodeString(IntToStr(Length(Src.Forms)))+
      ' форм-фізично='+UnicodeString(IntToStr(Length(Doc.Roots)))+
      ' слів-фізично='+UnicodeString(IntToStr(Length(Words)))+
      ' перший-д4=0011 лямбда-д4=0010 T5M=побайтово'+
      ' виконання=ні',False);
  finally
    Doc.Free;
    Src.Free;
  end;
end;

begin
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>
       #$2D#$2D#$D0#$B4#$D0#$BE#$D0#$BF#$D1#$83#$D1#$81#$D0#$BA) then begin
    WriteUtf8Line('Використання: senscore1dopus --допуск КОРІНЬ-РЕПОЗИТОРІЮ',True);
    Halt(64);
  end;
  try
    Admit(ParamStr(2));
  except
    on E:Exception do begin
      WriteUtf8Line('CORE1-ДОПУСК-ВІДМОВА: '+UnicodeString(E.Message),True);
      Halt(2);
    end;
  end;
end.
