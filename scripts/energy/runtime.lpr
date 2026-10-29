{ Вимірювальний host harness, не новий закон або evaluator SENS.
  Один TBinaryExecutor живе протягом процесу; кожен запит повторює
  повний чинний T5M/D2/binder/eval/output над незмінними фізичними байтами.
  RawByteString керуються FPC, Engine звільняється finally; checksum
  лише підтверджує кількість host-повторів, не є мовним результатом. }
program energy_runtime;
{$mode objfpc}{$H+}{$codepage utf8}
uses cwstring,SysUtils,Classes,wsm.t5m,wsm.binaryexec;
var Engine:TBinaryExecutor;
    Physical,Expected,Answer:RawByteString;
    Line:String;
    Count,I,Checksum:QWord;

function ReadBytes(const Path:String):RawByteString;
var F:TFileStream; Words:TExactWords;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise Exception.Create('Некоректний розмір фізичного файла');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
  DecodeT5M(Result,Words);
  if EncodeT5M(Words)<>Result then
    raise Exception.Create('Неканонічний T5M');
end;

begin
  Engine:=nil;
  try
    if ParamCount<>3 then
      raise Exception.Create('Потрібні authority, вхід.sens та очікуваний.sens');
    Physical:=ReadBytes(ParamStr(2));
    Expected:=ReadBytes(ParamStr(3));
    Engine:=TBinaryExecutor.Create(ParamStr(1));
    if Engine.ExecutePhysicalT5M(Physical)<>Expected then
      raise Exception.Create('Хибна фізична відповідь перед вимірюванням');
    WriteLn('READY'); Flush(Output);
    while not EOF(Input) do begin
      ReadLn(Line);
      if not TryStrToQWord(Line,Count) or (Count<1) or (Count>100000000) then
        raise Exception.Create('Кількість повторів поза host-межею');
      Checksum:=0;
      for I:=1 to Count do begin
        Answer:=Engine.ExecutePhysicalT5M(Physical);
        if Answer<>Expected then
          raise Exception.Create('Хибна фізична відповідь під час вимірювання');
        Checksum:=Checksum+Ord(Answer[1]);
      end;
      WriteLn('OK',#9,Count,#9,Checksum); Flush(Output);
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'ЕНЕРГІЯ-ВІДМОВА: ',E.Message);
      ExitCode:=1;
    end;
  end;
  Engine.Free;
end.
{ Питання: 1) Чому Physical не є текстом? 2) Що входить до одного
  повтору? 3) Чому checksum не замінює exact перевірку? 4) Чому один
  процес із багатьма запитами відрізняється від холодного запуску? }
