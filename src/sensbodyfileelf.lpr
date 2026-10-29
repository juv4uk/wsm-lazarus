{ G6.148 — нативний FILE→AOT для вже реалізованого зниження тіла SENS.
  Канонічні входи — фізичні packed T5M файли .sens, а не текстові
  проєкції. Цей CLI не тлумачить назви й не копіює законів Core1/Core4:
  лише передає exact тіло, D7-ключі та D24 атоми до wsm.lowerd24.
  Результат — справжній ELF64 ET_EXEC з exit(low8(value)).

  Параметри передаються тільки як окремі канонічні .sens документи.
  Вхідні RawByteString належать Run, а результат ELF — PublishNewELF64.
  Питання:
    1) Чому ім'я мусить зберігати всі сім бітів кожного D7 гліфа?
    2) Чому D24 atom не можна прийняти лише як десятковий host-текст?
    3) Чому тип ELF=2 — це host ABI, а не мовна координата D2?
    4) Що стається з файлом цілі при будь-якому винятку?
    5) Чому читання .lisp як canonical тут заборонене? }
program sensbodyfileelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.lowerd24,wsm.elfpublish,wsm.elfgeometry;

type EBodyFileCLIError=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Ok:Boolean;const Why:UnicodeString);
begin if not Ok then raise EBodyFileCLIError.Create(String(UA(Why))) end;

{ Строка FileName — лише host-шлях, НЕ SENS-ідентичність.
  Після закриття файлового потоку повний RawByteString — owned.
  Перевірка canonical exact через декодер та зворотний кодек,
  а не через розширення файлу чи текстове ім'я.
  Питання: хто звільняє TFileStream? Чому не довіряємо .sens-суфіксу?
  Чому квота байтів передує алокації? }
function ReadPhysical(const FileName:String;MaxBytes:SizeInt):RawByteString;
var F:TFileStream;W:TExactWords;
begin
  Need((FileName<>'') and (Length(FileName)<=4096) and
    (ExtractFileExt(FileName)='.sens'), 'джерело повинне бути файлом .sens');
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MaxBytes),'вхідний T5M перевищує квоту');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
  DecodeT5M(Result,W);
  Need(EncodeT5M(W)=Result,'не канонічний двійковий T5M');
end;

{ D7 лише механічне exact ім'я: D2:10, принаймні один W7, D2:01.
  Ніякого значення функції з гліфів не виводиться. Позичений фізичний
  ввід → результат owned повний двійковий ключ із усіх W7 без колізій.
  Питання: чому вимога хоча б одного W7? Чому 24 біти не стануть D7?
  Чому D2 framing перевіряється до компіляції? }
function NameBits(const Physical:RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  DecodeT5M(Physical,W);
  Need((Length(W)>=3) and (W[0]='10') and
    (W[High(W)]='01'),'не канонічний D7-список імені');
  Result:='';
  for I:=1 to High(W)-1 do begin
    Need(Length(W[I])=7,'імʼя має містити лише точні D7 слова');
    Result:=Result+W[I];
  end;
end;

{ Явний числовий домен через чинний numericplane; жодної адаптації
  D12 до D24 чи конверсії host integer. Результат лишається фізичним
  T5M, тому живе до завершення виклику LowerBody*.
  Питання: чому D12 не допустимий? Чому знак зберігається як біт?
  Чому не перетворюємо atom на Unicode? }
procedure CheckD24(const Physical:RawByteString);
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(Physical,24);
  Need((N.DomainWidth=24) and (Length(N.ExactBits)=24),
    'аргумент повинен бути exact D24');
end;

procedure SayError(const S:RawByteString);
var Stream:THandleStream;Msg:RawByteString;
begin
  Msg:=S+#10;
  Stream:=THandleStream.Create(TextRec(StdErr).Handle);
  try Stream.WriteBuffer(Msg[1],Length(Msg));finally Stream.Free end;
end;

procedure Run;
var Mode,Body,P1,P2,Self,A1,A2,Image:RawByteString;
    TwoArgs,Recursive:Boolean;G:TELFGeometry;OutName:String;
begin
  {$IFNDEF LINUX}
  Need(False,'потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  Need(False,'потрібен x86-64');
  {$ENDIF}
  Need(ParamCount>=1,'потрібен режим та фізичні файли');
  Mode:=RawByteString(ParamStr(1));
  TwoArgs:=(Mode=UA('--два-D24')) or
           (Mode=UA('--два-D24-самовиклик'));
  Recursive:=(Mode=UA('--один-D24-самовиклик')) or
             (Mode=UA('--два-D24-самовиклик'));
  Need((Mode=UA('--один-D24')) or
       (Mode=UA('--один-D24-самовиклик')) or TwoArgs,
       'невідомий режим тіла');
  if TwoArgs then begin
    if Recursive then Need(ParamCount=8,'потрібні тіло, два імені, self, два D24 та ELF')
    else Need(ParamCount=7,'потрібні тіло, два імені, два D24 та ELF');
  end else begin
    if Recursive then Need(ParamCount=6,'потрібні тіло, імʼя, self, D24 та ELF')
    else Need(ParamCount=5,'потрібні тіло, імʼя, D24 та ELF');
  end;
  OutName:=ParamStr(ParamCount);
  Need((OutName<>'') and (Length(OutName)<=4096) and
       (ExtractFileExt(OutName)='.elf'),'ціль повинна бути новим .elf');
  Body:=ReadPhysical(ParamStr(2),8192);
  P1:=ReadPhysical(ParamStr(3),512);
  Need(NameBits(P1)<>'','порожній точний D7 параметр');
  P2:='';Self:='';A1:='';A2:='';
  if TwoArgs then begin
    P2:=ReadPhysical(ParamStr(4),512);
    Need(NameBits(P2)<>NameBits(P1),'дубльований точний D7 параметр');
    if Recursive then begin
      Self:=ReadPhysical(ParamStr(5),512);
      A1:=ReadPhysical(ParamStr(6),64);
      A2:=ReadPhysical(ParamStr(7),64);
    end else begin
      A1:=ReadPhysical(ParamStr(5),64);
      A2:=ReadPhysical(ParamStr(6),64);
    end;
    CheckD24(A1);CheckD24(A2);
    if Self<>'' then
      Need((NameBits(Self)<>NameBits(P1)) and
           (NameBits(Self)<>NameBits(P2)),
           'самовиклик не може затьмарити параметр');
    Image:=LowerBodyTwoParamsWithSelfELF(Body,P1,P2,A1,A2,Self);
  end else begin
    if Recursive then begin
      Self:=ReadPhysical(ParamStr(4),512);
      A1:=ReadPhysical(ParamStr(5),64);
    end else
      A1:=ReadPhysical(ParamStr(4),64);
    CheckD24(A1);
    if Self<>'' then
      Need(NameBits(Self)<>NameBits(P1),
        'самовиклик не може затьмарити параметр');
    Image:=LowerBodyWithSelfELF(Body,P1,A1,Self);
  end;
  PublishNewELF64(OutName,Image,2,G);
  Writeln('SENS-BODY-AOT-ELF64 bytes=',G.FileBytes,' args=',Ord(TwoArgs)+1,
    ' self=',Ord(Recursive),' result=EXIT_LOW8');
end;

begin
  try Run
  except on E:Exception do begin
    SayError(UA('ТІЛО-SENS-AOT-ВІДМОВА: ')+RawByteString(E.Message));
    ExitCode:=2;
  end end;
end.
