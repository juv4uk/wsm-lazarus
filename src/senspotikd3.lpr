{ G3.19 — одноразовий фізичний stdin/stdout канал D3.
  ЖОДНОГО Lisp/Unicode парсингу у потоці: приймаємо й повертаємо
  лише незмінні паковані T5M байти, pinned закони виконує wsm.d3batch.
  Це не постійний REPL і не Core4. }
program senspotikd3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d3batch;

function Ukr(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Run;
var
  Source, Sink:THandleStream;
  Chunk:array[0..4095] of Byte;
  Physical, Answer:RawByteString;
  Words:TExactWords;
  Got, Used, Count:SizeInt;
begin
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>Ukr('--потік'))
    or (ParamStr(2)='') then begin
    WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3: використання senspotikd3 --потік корінь-sens; stdin/stdout=тільки-фізичний-T5M'));
    ExitCode:=64;
    Exit;
  end;

  { Фізичний stdin читається ДО виконання. EOF не означає кінець
    окремої форми: тільки D2-обрамлення задає корені пакета. }
  Source:=nil; Sink:=nil; Used:=0; Physical:=''; Answer:='';
  try
    Source:=THandleStream.Create(TextRec(Input).Handle);
    repeat
      Got:=Source.Read(Chunk,SizeOf(Chunk));
      if Got=0 then Break;
      if (Got<0) or (Got>MAX_T5M_FILE_BYTES-Used) then
        raise Exception.Create('вхідний фізичний потік більший за межу T5M');
      SetLength(Physical,Used+Got);
      Move(Chunk[0],Physical[Used+1],Got);
      Inc(Used,Got);
    until False;
    FreeAndNil(Source);

    { Успіх усіх форм — єдина умова публікації stdout.
      Вихідні байти будуються лише на наявному pinned D3 evaluator. }
    ExecutePhysicalD3Batch(Physical,RawByteString(ParamStr(2)),Answer,Count);
    if (Count<1) or (Count>64) or (Length(Answer)<1) or
       (Length(Answer)>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('некоректний результат обмеженого D3 пакета');
    DecodeT5M(Answer,Words);
    if (Length(Words)=0) or (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('відповідь не є канонічним фізичним T5M');

    { Не друкувати лог у stdout. Heaptrc (-gh) у цьому executable
      також ЗАБОРОНЕНИЙ: він домішав би свій текст до двійкових байтів.
      Якщо ОС зірве сам WriteBuffer, частковий OS pipe не відкочується. }
    Sink:=THandleStream.Create(TextRec(Output).Handle);
    Sink.WriteBuffer(Answer[1],Length(Answer));
  except
    on E:ED3BatchError do begin
      WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3 форма='),E.FormIndex,
        Ukr(' слово='),E.WordIndex,': ',E.Message);
      ExitCode:=2;
    end;
    on E:Exception do begin
      WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3: '),E.Message);
      ExitCode:=2;
    end;
  end;
  Sink.Free;
  Source.Free;
end;

{ G5.34: це host-обрамлення за вже чинним senscore4kanal.
  Запит u32le length + physical T5M; відповідь status:u8 + u32le + payload.
  Одне ядро D3 виконує кожний запит незалежно; це не REPL і не
  середовище із збереженими визначеннями. }
const MaxD3DiagnosticBytes=4096;
type ED3ChannelError=class(Exception);

function ReadChannelExact(S:TStream;var Target;N:SizeInt;
  AllowEOF:Boolean):Boolean;
var P:PByte; Done,Got:SizeInt;
begin
  P:=@Target; Done:=0; Result:=False;
  while Done<N do begin
    Got:=S.Read(P[Done],N-Done);
    if Got<=0 then begin
      if AllowEOF and (Done=0) then Exit(False);
      raise ED3ChannelError.Create('обірваний фізичний host-кадр');
    end;
    Inc(Done,Got);
  end;
  Result:=True;
end;

function ReadFrameSize(const H:array of Byte):QWord;
begin
  Result:=QWord(H[0]) or (QWord(H[1]) shl 8) or
    (QWord(H[2]) shl 16) or (QWord(H[3]) shl 24);
end;

procedure SendChannelReply(S:TStream;Status:Byte;const Payload:RawByteString);
var H:array[0..4] of Byte;N:LongWord;
begin
  if (Status>1) or (Length(Payload)<1) or
    (Length(Payload)>MAX_T5M_FILE_BYTES) then
    raise ED3ChannelError.Create('недопустима довжина фізичної відповіді');
  N:=LongWord(Length(Payload));
  H[0]:=Status;
  H[1]:=Byte(N and $ff);
  H[2]:=Byte((N shr 8) and $ff);
  H[3]:=Byte((N shr 16) and $ff);
  H[4]:=Byte((N shr 24) and $ff);
  S.WriteBuffer(H,SizeOf(H));
  S.WriteBuffer(Payload[1],Length(Payload));
end;

procedure RunChannel;
var
  Source,Sink:THandleStream;
  Header:array[0..3] of Byte;
  Size:QWord;
  Physical,Answer,Detail:RawByteString;
  Words:TExactWords;
  Completed:SizeInt;
  HadFault:Boolean;
begin
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Sink:=THandleStream.Create(TextRec(Output).Handle);
    try
      HadFault:=False;
      while ReadChannelExact(Source,Header,4,True) do begin
        Size:=ReadFrameSize(Header);
        { Великі та обірвані host-кадри — фатальна протокольна
          помилка, не мовна помилка D3; повної відповіді немає. }
        if Size>MAX_T5M_FILE_BYTES then
          raise ED3ChannelError.Create('host-кадр перевищує межу T5M');
        SetLength(Physical,SizeInt(Size));
        if Size>0 then
          ReadChannelExact(Source,Physical[1],SizeInt(Size),False);
        try
          if Size=0 then
            raise ED3ChannelError.Create('порожній фізичний D3 кадр');
          Answer:=''; Completed:=0;
          ExecutePhysicalD3Batch(Physical,
            RawByteString(ParamStr(2)),Answer,Completed);
          if (Completed<1) or (Completed>64) or
            (Length(Answer)<1) or
            (Length(Answer)>MAX_T5M_FILE_BYTES) then
            raise ED3ChannelError.Create('неприпустимий D3 пакет відповідей');
          DecodeT5M(Answer,Words);
          if (Length(Words)=0) or (EncodeT5M(Words)<>Answer) then
            raise ED3ChannelError.Create('неканонічний T5M результат D3');
          SendChannelReply(Sink,0,Answer);
        except
          on E:Exception do begin
            HadFault:=True;
            if E is ED3BatchError then
              Detail:=Ukr('форма=')+
                RawByteString(IntToStr(ED3BatchError(E).FormIndex))+
                Ukr(' слово=')+
                RawByteString(IntToStr(ED3BatchError(E).WordIndex))+
                ': '+RawByteString(E.Message)
            else
              Detail:=RawByteString(E.Message);
            if Length(Detail)>MaxD3DiagnosticBytes then
              SetLength(Detail,MaxD3DiagnosticBytes);
            if Detail='' then Detail:=Ukr('фізичне виконання відхилено');
            SendChannelReply(Sink,1,Detail);
          end;
        end;
        Physical:=''; Answer:='';
      end;
      { Негативний status не завершує процес, але фінальний exit
        відрізняє його від сесії без жодної семантичної помилки. }
      if HadFault then ExitCode:=2;
    finally Sink.Free; end;
  finally Source.Free; end;
end;

begin
  if (ParamCount=2) and
    ((RawByteString(ParamStr(1))=Ukr('--канал')) or
     (RawByteString(ParamStr(1))=Ukr('--канал-пакет'))) and
    (ParamStr(2)<>'') then
    try RunChannel;
    except
      on E:Exception do begin
        WriteLn(StdErr,Ukr('ПОМИЛКА-КАНАЛ-D3: '),E.Message);
        ExitCode:=2;
      end;
    end
  else
    Run;
end.
