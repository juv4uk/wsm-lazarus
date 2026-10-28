{ G5.22 — обмежений двійковий host-канал до справжнього pinned Core4.
  Запит: u32le довжина + канонічний T5M; відповідь: статус + u32le + байти.
  Це НЕ формат .sens, текстова проєкція або повний мовний REPL. }
program senscore4kanal;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m;
const MaxFrameBytes = 1024 * 1024;
      MaxDiagnosticBytes = 4096;
type EChannelError = class(Exception);

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ReadExact(S:TStream; var Target; N:SizeInt;
  AllowCleanEOF:Boolean):Boolean;
var P:PByte; Done,Count:SizeInt;
begin
  Result:=False; P:=@Target; Done:=0;
  while Done<N do begin
    Count:=S.Read(P[Done],N-Done);
    if Count<=0 then begin
      if AllowCleanEOF and (Done=0) then Exit(False);
      raise EChannelError.Create('обірваний фізичний кадр host-каналу');
    end;
    Inc(Done,Count);
  end;
  Result:=True;
end;

function FrameLength(const Header:array of Byte):QWord;
begin
  Result:=QWord(Header[0]) or (QWord(Header[1]) shl 8) or
          (QWord(Header[2]) shl 16) or (QWord(Header[3]) shl 24);
end;

{ Повний кадр готується до запису; stdout не є текстовим протоколом.
  S — borrowed host stream, Payload — exact T5M або UTF-8 діагностика. }
procedure WriteReply(S:TStream; Status:Byte; const Payload:RawByteString);
var H:array[0..4] of Byte; N:LongWord;
begin
  if (Status>1) or (Length(Payload)<1) or
     (Length(Payload)>MaxFrameBytes) then
    raise EChannelError.Create('недопустимий розмір або стан відповіді');
  N:=LongWord(Length(Payload));
  H[0]:=Status;
  H[1]:=Byte(N and $FF);
  H[2]:=Byte((N shr 8) and $FF);
  H[3]:=Byte((N shr 16) and $FF);
  H[4]:=Byte((N shr 24) and $FF);
  S.WriteBuffer(H,SizeOf(H));
  S.WriteBuffer(Payload[1],Length(Payload));
end;

procedure RunChannel(const Root:String);
var
  Runtime:TCore4Runtime;
  Source,Sink:THandleStream;
  H:array[0..3] of Byte;
  Size:QWord;
  InPhysical,OutPhysical,Detail:RawByteString;
  Words:TExactWords;
  HadFault:Boolean;
begin
  Runtime:=TCore4Runtime.Create(Root);
  try
    Source:=THandleStream.Create(TextRec(Input).Handle);
    try
      Sink:=THandleStream.Create(TextRec(Output).Handle);
      try
        HadFault:=False;
        while ReadExact(Source,H,4,True) do begin
          Size:=FrameLength(H);
          if Size>MaxFrameBytes then
            raise EChannelError.Create('кадр перевищує обмеження 1 МіБ');
          SetLength(InPhysical,SizeInt(Size));
          if Size>0 then
            ReadExact(Source,InPhysical[1],SizeInt(Size),False);
          try
            if Size=0 then
              raise EChannelError.Create('порожній двійковий кадр');
            OutPhysical:=Runtime.ExecutePhysicalCall(InPhysical);
            DecodeT5M(OutPhysical,Words);
            if (Length(Words)<>1) or (EncodeT5M(Words)<>OutPhysical) then
              raise EChannelError.Create('Core4 повернув неканонічний T5M');
            WriteReply(Sink,0,OutPhysical);
          except on E:Exception do begin
            HadFault:=True;
            Detail:=RawByteString(E.Message);
            if Length(Detail)>MaxDiagnosticBytes then
              SetLength(Detail,MaxDiagnosticBytes);
            if Length(Detail)=0 then Detail:=Ukr('помилка виконання');
            WriteReply(Sink,1,Detail);
          end end;
          InPhysical:=''; OutPhysical:='';
        end;
        if HadFault then ExitCode:=2;
      finally Sink.Free end;
    finally Source.Free end;
  finally Runtime.Free end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>Ukr('--канал')) then begin
    WriteLn(StdErr,Ukr('Використання: senscore4kanal --канал КОРІНЬ'));
    ExitCode:=64;
  end else
    try RunChannel(ParamStr(2));
    except on E:Exception do begin
      WriteLn(StdErr,Ukr('ПОМИЛКА ФІЗИЧНОГО КАНАЛУ: '),E.Message);
      ExitCode:=2;
    end end;
end.
