{ G5.59 — довгоживучий host-сеанс фізичного SENS без .lisp перетворення.
  Запит: u32le довжина + канонічні packed T5M байти ОДНІЄЇ форми.
  Відповідь: status:u8 + 1-based word:u32le + len:u32le + payload.
  status=0: виконаний канонічний T5M; status=1: українська діагностика.
  Host-кадри НЕ є законами/значеннями SENS, це НЕ повний REPL. }
program sensfizseans;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec;

const
  MaxInputBytes = 65536;
  MaxReplyBytes = 65536;
type
  EPhysicalSessionError = class(Exception);

function UA(const Text:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Text));end;

function ReadExactly(S:TStream; var Dest; Count:SizeInt;
  AllowCleanEOF:Boolean):Boolean;
var P:PByte; Used,Got:SizeInt;
begin
  P:=@Dest; Used:=0;
  while Used<Count do begin
    Got:=S.Read(P[Used],Count-Used);
    if Got<=0 then begin
      if AllowCleanEOF and (Used=0) then Exit(False);
      raise EPhysicalSessionError.Create('обірвано заголовок або тіло фізичного host-кадру');
    end;
    Inc(Used,Got);
  end;
  Result:=True;
end;

function ReadLE32(const H:array of Byte):QWord;
begin
  Result:=QWord(H[0]) or (QWord(H[1]) shl 8) or
    (QWord(H[2]) shl 16) or (QWord(H[3]) shl 24);
end;

procedure WriteLE32(S:TStream; N:QWord);
var I:SizeInt; B:Byte;
begin
  if N>High(LongWord) then
    raise EPhysicalSessionError.Create('неприпустиме 32-бітове поле host-кадру');
  for I:=0 to 3 do begin
    B:=Byte((N shr (8*I)) and $FF);
    S.WriteBuffer(B,1);
  end;
end;

{ Один виконавець існує між запитами, але він НЕ обіцяє мутацію
  лексичного середовища. Physical — власні тимчасові байти кадру,
  Answer — нові канонічні байти T5M (успіх) або UTF-8 (відмова).
  Жодного часткового stdout до обчислення ВСІЄЇ відповіді.
  Питання: Чому status не D1? Хто володіє байтами? Чому кадр не
  стає SENS програмою? Які помилки не дозволяють продовження? }
procedure Run;
var Engine:TBinaryExecutor;
    Source,Sink:THandleStream;
    Header:array[0..3] of Byte;
    Size,WordAt:QWord;
    Physical,Answer,Encoded:RawByteString;
    Status:Byte;
    Reply:TMemoryStream;
begin
  Engine:=TBinaryExecutor.Create('external/sens');
  try
    Source:=THandleStream.Create(TextRec(Input).Handle);
    try
      Sink:=THandleStream.Create(TextRec(Output).Handle);
      try
        while ReadExactly(Source,Header,4,True) do begin
          Size:=ReadLE32(Header);
          if (Size=0) or (Size>MaxInputBytes) then
            raise EPhysicalSessionError.Create(
              'довжина фізичного host-кадру поза межами 1..65536');
          SetLength(Physical,SizeInt(Size));
          ReadExactly(Source,Physical[1],SizeInt(Size),False);
          Status:=0;WordAt:=0;
          try
            Answer:=Engine.ExecutePhysicalT5M(Physical);
          except
            on E:EBinaryExecutionError do begin
              Status:=1;
              if (E.WordIndex<0) or (QWord(E.WordIndex)>High(LongWord)) then
                raise EPhysicalSessionError.Create('недопустимий індекс слова');
              WordAt:=QWord(E.WordIndex);
              Answer:=RawByteString(E.Message);
              if Answer='' then Answer:='виконання відхилено';
            end;
          end;
          if (Length(Answer)=0) or (Length(Answer)>MaxReplyBytes) then
            raise EPhysicalSessionError.Create(
              'порожня або надмірна відповідь виконавця');
          Reply:=TMemoryStream.Create;
          try
            Reply.WriteBuffer(Status,1);
            WriteLE32(Reply,WordAt);
            WriteLE32(Reply,Length(Answer));
            Reply.WriteBuffer(Answer[1],Length(Answer));
            SetLength(Encoded,SizeInt(Reply.Size));
            Reply.Position:=0;
            Reply.ReadBuffer(Encoded[1],Length(Encoded));
          finally Reply.Free; end;
          { Потік ОС може обірватися при записі; rollback уже
            відправлених байтів не гарантується. }
          Sink.WriteBuffer(Encoded[1],Length(Encoded));
          Physical:=''; Answer:=''; Encoded:='';
        end;
      finally Sink.Free;end;
    finally Source.Free;end;
  finally Engine.Free;end;
end;

begin
  if (ParamCount<>1) or
     (RawByteString(ParamStr(1))<>
       #$2D#$2D#$D1#$81#$D0#$B5#$D0#$B0#$D0#$BD#$D1#$81) then begin
    WriteLn(StdErr,UA('Використання: sensfizseans --сеанс (приватний фізичний host-канал)'));
    ExitCode:=64;
  end else
    try Run;
    except
      on E:Exception do begin
        WriteLn(StdErr,UA('ФІЗИЧНИЙ-СЕАНС-ПОМИЛКА: '),E.Message);
        ExitCode:=2;
      end;
    end;
end.
