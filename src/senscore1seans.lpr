{ G5.67 — довгоживучий фізичний host-сеанс першого pinned Core1 замикання.
  Приватний transport: запит u32le довжина + canonical T5M;
  відповідь status:u8 + u32le довжина + T5M або UTF-8 діагностика.
  Кадрування НЕ є синтаксисом/законом SENS. Усі виклики виконуються
  тільки вже перевіреним TCore1FirstRuntime із pinned core1.sens.
  Непідтримані форми відхиляються без підміни D1/D3 або D12+.
  Це не загальний REPL. }
program senscore1seans;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1first;

const
  MaxFrameBytes = 65536; { обмеження host-каналу, не закон SENS }
  ReplyOk = 0;
  ReplyError = 1;

type
  ECore1SessionError = class(Exception);

function Uk(const Value:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(Value));
end;

{ Source позичений від стандартного потоку; не Seek/Size, бо stdin — pipe.
  False повертається лише на ЧИСТОМУ EOF до першого байта заголовка.
  Помилка посеред кадру зупиняє канал без відповіді за цей кадр.
  Питання: чому частковий заголовок не дорівнює EOF?
  Хто володіє Dest? Чому довжина перевіряється до SetLength? }
function ReadExactly(Source:TStream; var Dest; Count:SizeInt;
  AllowEOF:Boolean):Boolean;
var P:PByte; Done,ReadCount:SizeInt;
begin
  P:=@Dest;
  Done:=0;
  while Done<Count do begin
    ReadCount:=Source.Read(P[Done],Count-Done);
    if ReadCount<=0 then begin
      if AllowEOF and (Done=0) then Exit(False);
      raise ECore1SessionError.Create(Uk('обірвано фізичний host-кадр'));
    end;
    Inc(Done,ReadCount);
  end;
  Result:=True;
end;

function Little32(const Bytes:array of Byte):QWord;
begin
  Result:=QWord(Bytes[0]) or (QWord(Bytes[1]) shl 8) or
    (QWord(Bytes[2]) shl 16) or (QWord(Bytes[3]) shl 24);
end;

procedure Put32(Sink:TStream; Value:QWord);
var Bytes:array[0..3] of Byte; I:SizeInt;
begin
  if Value>High(LongWord) then
    raise ECore1SessionError.Create(Uk('надмірна довжина відповіді'));
  for I:=0 to 3 do Bytes[I]:=Byte((Value shr (I*8)) and $FF);
  Sink.WriteBuffer(Bytes,SizeOf(Bytes));
end;

{ Physical — власний RawByteString із stdin; Words — тимчасові точні
  двійкові слова. Повторно пакуємо тільки для перевірки канонічності,
  а НЕ для виведення мовних законів/доменів із ширини чи spelling.
  Результат створює ТІЛЬКИ pinned runtime, жодного local dispatch.
  Питання: чому UTF-8 .lisp не допускається як T5M?
  Чому D7 лишається даними? Навіщо рівність packed bytes?
  Чому помилка T5M не змінює семантику наступної форми? }
function ExecuteCanonical(Runtime:TCore1FirstRuntime;
  const Physical:RawByteString):RawByteString;
var Words:TExactWords;
begin
  DecodeT5M(Physical,Words);
  if EncodeT5M(Words)<>Physical then
    raise ECore1SessionError.Create(Uk('не канонічне фізичне T5M'));
  Result:=Runtime.ExecutePhysicalCall(Physical);
  if (Length(Result)<1) or (Length(Result)>MaxFrameBytes) then
    raise ECore1SessionError.Create(Uk('відповідь Core1 за межею host-кадру'));
  DecodeT5M(Result,Words);
  if EncodeT5M(Words)<>Result then
    raise ECore1SessionError.Create(Uk('виконавець повернув неканонічне T5M'));
end;

{ Один Runtime живе від першого до останнього кадру. Під час
  синтаксичної/семантичної відмови лише ця форма має status=1;
  наступний запит використовує ТЕ САМЕ замикання. Збій кадрування
  фатальний, оскільки невідомо, де починається наступний кадр.
  Власність Source/Sink/Runtime — локальна, звільнення через finally.
  Питання: чому status — host byte, а не D1?
  Чому після обірваного payload не можна продовжити?
  Що гарантує відсутність часткової відповіді на помилку виконання?
  Чи можна відкотити вже записані байти stdout при EPIPE? Ні. }
procedure Run(const WorkspaceRoot:String);
var Runtime:TCore1FirstRuntime;
    Source,Sink:THandleStream;
    Header:array[0..3] of Byte;
    FrameSize:QWord;
    Physical,Answer:RawByteString;
    Status:Byte;
begin
  Runtime:=TCore1FirstRuntime.Create(
    IncludeTrailingPathDelimiter(ExpandFileName(WorkspaceRoot))+
    'external'+PathDelim+'sens',WorkspaceRoot);
  try
    Source:=THandleStream.Create(TextRec(Input).Handle);
    try
      Sink:=THandleStream.Create(TextRec(Output).Handle);
      try
        while ReadExactly(Source,Header,SizeOf(Header),True) do begin
          FrameSize:=Little32(Header);
          if (FrameSize<1) or (FrameSize>MaxFrameBytes) then
            raise ECore1SessionError.Create(Uk('довжина кадру поза межею 1..65536'));
          SetLength(Physical,SizeInt(FrameSize));
          ReadExactly(Source,Physical[1],SizeInt(FrameSize),False);
          Status:=ReplyOk;
          try
            Answer:=ExecuteCanonical(Runtime,Physical);
          except
            on E:Exception do begin
              Status:=ReplyError;
              Answer:=RawByteString(E.Message);
              if Answer='' then Answer:=Uk('виклик Core1 відхилено');
            end;
          end;
          if Length(Answer)>MaxFrameBytes then begin
            Status:=ReplyError;
            Answer:=Uk('діагностика Core1 перевищила межу');
          end;
          if Length(Answer)=0 then
            raise ECore1SessionError.Create(Uk('порожня відповідь Core1'));
          { Тільки після повної обробки відповіді — будь-який stdout. }
          Sink.WriteBuffer(Status,1);
          Put32(Sink,Length(Answer));
          Sink.WriteBuffer(Answer[1],Length(Answer));
          Physical:='';Answer:='';
        end;
      finally Sink.Free end;
    finally Source.Free end;
  finally Runtime.Free end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>Uk('--сеанс-core1')) or
     (ParamStr(2)='') then begin
    WriteLn(StdErr,Uk('Використання: senscore1seans --сеанс-core1 КОРІНЬ'));
    ExitCode:=64;
  end else
    try Run(ParamStr(2))
    except
      on E:Exception do begin
        WriteLn(StdErr,Uk('CORE1-СЕАНС-ПОМИЛКА: '),E.Message);
        ExitCode:=2;
      end;
    end;
end.
