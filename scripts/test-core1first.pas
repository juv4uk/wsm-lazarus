{ Core1.2 — незалежні фізичні позитиви/негативи замикання першого pinned DEFINE.
  Реальний D4 механізм запускає вже злитий runtime, не тестовий код. }
program testcore1first;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.core1first,wsm.t5m,wsm.d2source;
var
  C:TCore1First;
  Name, Changed, Original,Mutant,Physical:RawByteString;
  Words:TExactWords;
  D:TD2Document;
  BodyWord:SizeInt;
  Checks:SizeInt;

procedure Check(OK:Boolean;const Text:String);
begin
  Inc(Checks);
  if not OK then raise Exception.Create('CORE1-ПРОВАЛ: '+Text);
end;

procedure Save(const Path:String;const PhysicalBytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if PhysicalBytes<>'' then F.WriteBuffer(PhysicalBytes[1],Length(PhysicalBytes));
  finally F.Free end;
end;
function Read(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead);
  try
    SetLength(Result,F.Size);
    if Result<>'' then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Фізичний виклик без людської текстової інтерпретації. Значення
  передаються лише як точні слова, D4:1110 виконує спільний runtime.
  Питання: що означає W24? Які T5M-байти очікуємо? Де D2 framing? }
function Arg(const Values:TExactWords):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Values)+3);
  W[0]:='10'; W[1]:='1110';
  for I:=0 to High(Values) do W[I+2]:=Values[I];
  W[High(W)]:='01';
  Result:=EncodeT5M(W);
end;

procedure Expect(const Payload,Expected:RawByteString;const LabelText:String);
var Actual:RawByteString; W:TExactWords;
begin
  Actual:=C.ExecutePhysical(Name,Payload);
  DecodeT5M(Actual,W);
  Check((Length(W)=1) and (W[0]=Expected),
    LabelText+' — точний результат');
  Check(Actual=EncodeT5M(W),LabelText+' — канонічні байти');
end;

procedure Reject(const LabelText,NameBits,Payload:RawByteString);
begin
  try
    C.ExecutePhysical(NameBits,Payload);
  except on E:Exception do begin
    Check(E.Message<>'',LabelText+' — діагностика');
    Exit;
  end;end;
  raise Exception.Create('CORE1-ПРОВАЛ: не відхилено '+String(LabelText));
end;

procedure RejectFile(const Path,LabelText:String);
var Candidate:TCore1First;
begin
  Candidate:=nil;
  try
    Candidate:=TCore1First.Create(ParamStr(1),Path);
  except on E:Exception do begin
    Check(E.Message<>'',LabelText+' — причина');
    Exit;
  end;end;
  Candidate.Free;
  raise Exception.Create('CORE1-ПРОВАЛ: прийнято '+LabelText);
end;

begin
  Checks:=0;
  if ParamCount<>3 then
    raise Exception.Create('потрібні ROOT core1.sens TEST-DIR');
  Original:=Read(ParamStr(2));
  C:=TCore1First.Create(ParamStr(1),ParamStr(2));
  try
    Name:=C.PhysicalName;
    Check((Length(Name)>0) and ((Length(Name) mod 7)=0),
      'точний D7 ідентифікатор завантажено');
    { Upstream виконає ТОЧНО lowered bytes, без реконструкції SENS
      форми чи семантики в Python/Bash. Test-dir має lifetime TMP. }
    Save(IncludeTrailingPathDelimiter(ParamStr(3))+'оракул-ні.sens',
      C.LowerPhysicalCall(Name,Arg(TExactWords(['1','0','1']))));
    Save(IncludeTrailingPathDelimiter(ParamStr(3))+'оракул-так.sens',
      C.LowerPhysicalCall(Name,Arg(TExactWords(['0','1','0']))));
    Expect(Arg(TExactWords(['1','0','1'])),'0','другий з трьох D1');
    Expect(Arg(TExactWords(['0','1','0'])),'1','другий з трьох D1 — 1');
    Expect(Arg(TExactWords(['1','000000000000000000000000','0'])),
      '000000000000000000000000','другий з D24 з провідними нулями');
    Changed:=Copy(Name,1,Length(Name));
    if Changed[1]='0' then Changed[1]:='1' else Changed[1]:='0';
    Reject('один біт D7 імені',Changed,Arg(TExactWords(['1','0'])));
    Reject('недостатньо елементів',Name,Arg(TExactWords(['1'])));
    Reject('неправильна фізична D4 голова',Name,
      EncodeT5M(TExactWords(['10','1001','1','01'])));
    Reject('порожній T5M',Name,'');
    Reject('зіпсований T5M',Name,Arg(TExactWords(['1','0']))+#243);
    Reject('два корені',Name,
      EncodeT5M(TExactWords(['10','1110','1','0','01','10','1110','1','0','01'])));
    Expect(Arg(TExactWords(['0','1'])),'1','відновлення після негативів');
    DecodeT5M(Original,Words);
    D:=ParseD2WordsWide(Words);
    try
      BodyWord:=D.Roots[0].Children[2].Children[2].Children[0].WordIndex;
    finally D.Free end;
    Check(Words[BodyWord-1]='1001','оригінальний pinned D4:1001');
    Words[BodyWord-1]:='1000';
    Mutant:=EncodeT5M(Words);
    Save(IncludeTrailingPathDelimiter(ParamStr(3))+'змінене-тіло.sens',Mutant);
    RejectFile(IncludeTrailingPathDelimiter(ParamStr(3))+'змінене-тіло.sens',
      'один змінений біт D4 тіла');
    Save(IncludeTrailingPathDelimiter(ParamStr(3))+'пізня-корупція.sens',Original+#243);
    RejectFile(IncludeTrailingPathDelimiter(ParamStr(3))+'пізня-корупція.sens',
      'пошкоджений останній T5M байт');
    Expect(Arg(TExactWords(['1','0'])),'0','виконання після відхилень');
    WriteLn('CORE1-FIRST-PASS checked=',Checks,
      ' pinned=так real-FPC=так closure=first-only',
      ' GC=not-integrated whole-Core1=not-claimed');
  finally C.Free end;
end.
