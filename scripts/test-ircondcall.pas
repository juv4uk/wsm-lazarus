{ G6.122 — фізична D3:110 → verified IR → host JZ/JMP + shared CALL.
  Canonical .sens witnesses create existing EncodeT5M, not text parser.
  Test compares real native ELF, existing baseline ELF, and independent
  pinned Rust/Zig SENS oracle (in shell), including structural D3:000.
  Inputs borrowed; images and snapshots owned per test; saved files
  belong to temporary test directory and are cleared by harness.
  Питання: 1) Чому baseline ELF лише другий механічний еталон?
  2) Чому D3:000 не записуємо як нуль D1?
  3) Чим відрізняється CALL opcode від SENS bit string?
  4) Чому треба фактично запустити ELF, не лише його розібрати?
  5) Чому негатив має не публікувати жодного образу? }
program test_ircondcall;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.ircond,wsm.ircondcall,wsm.elfgeometry;
var Dir:String;Passed,Rejected,CallsTotal:SizeInt;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;
procedure Check(Yes:Boolean;const Why:String);
begin
  if not Yes then raise Exception.Create('G6_122_FAIL: '+Why)
end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end
end;
function CountByte(const Data:RawByteString;Ch:AnsiChar):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=1 to Length(Data) do if Data[I]=Ch then Inc(Result)
end;
procedure Positive(const Name,ExpectedWord:RawByteString;
  const SourceWords:array of RawByteString);
var Source,Image,Baseline,Expected,Oracle,Machine:RawByteString;
    L:TLoweredIRCond;Geom:TELFGeometry;Decoded:TExactWords;
    NeedCalls,I:SizeInt;
begin
  Source:=EncodeT5M(W(SourceWords));
  LowerPinnedIRCond(Source,'external/sens',L);
  Check(L.Count<=2,Name+': тест поза заявленим host профілем');
  NeedCalls:=0;
  for I:=0 to L.Count-1 do begin
    if L.Clauses[I].TestValue.Kind=1 then Inc(NeedCalls);
    if L.Clauses[I].ExpressionValue.Kind=1 then Inc(NeedCalls);
  end;
  Image:=BuildIRCondCallELF(Source,'external/sens');
  Baseline:=BuildPinnedIRCondELF(Source,'external/sens');
  Check(Image=BuildIRCondCallELF(Source,'external/sens'),
    Name+': невідтворювані машинні байти');
  Check(Image<>Baseline,Name+': не виявлено нового CALL/JZ backend');
  VerifySENSELF64(Image,Geom);
  Check((Geom.Kind=3) and (Geom.Entry=120) and
    (Geom.FileBytes=Length(Image)) and
    (Geom.MachineBytes<=256) and (Geom.MachineBytes>35),
    Name+': зламана ELF64 PIE геометрія');
  Machine:=Copy(Image,121,Length(Image)-120);
  Check(CountByte(Machine,#$E8)=NeedCalls,
    Name+': кількість shared CALL відрізняється від pinned lower');
  Check(Pos(#$39#$F7#$0F#$94#$C0#$0F#$B6#$C0#$C3,Machine)>0,
    Name+': спільна підпрограма CMP/SETE/RET відсутня');
  if L.Count>0 then
    Check((Pos(#$0F#$84,Machine)>0) and (CountByte(Machine,#$E9)>=2),
      Name+': немає JZ/JMP rel32 для відкладених виразів');
  Expected:=EncodeT5M(W([ExpectedWord]));
  DecodeT5M(Expected,Decoded);
  Check((Length(Decoded)=1) and (Decoded[0]=ExpectedWord),
    Name+': пошкоджений еталон фізичного T5M');
  if ExpectedWord='000' then Oracle:='()'+#10
  else Oracle:=ExpectedWord+#10;
  Save(Name+'.sens',Source);
  Save(Name+'.call.elf',Image);
  Save(Name+'.old.elf',Baseline);
  Save(Name+'.expected.sens',Expected);
  Save(Name+'.oracle.txt',Oracle);
  Inc(Passed);
  Inc(CallsTotal,NeedCalls);
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Image:RawByteString;Failed:Boolean;MessageText:String;
begin
  Image:='';Failed:=False;MessageText:='';
  try Image:=BuildIRCondCallELF(Physical,'external/sens')
  except on E:Exception do begin Failed:=True;MessageText:=E.Message end end;
  Check(Failed and (Image='') and (Length(MessageText)>3),
    Name+': пошкоджений source не відхилено атомарно');
  Inc(Rejected);
end;
procedure Negative(const Name:String;const Parts:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(W(Parts))) end;

begin
  Check((ParamCount=1) and DirectoryExists(ParamStr(1)),
    'потрібен існуючий тимчасовий каталог');
  Dir:=ParamStr(1);Passed:=0;Rejected:=0;CallsTotal:=0;

  Positive('порожня','000',['10','110','01']);
  Positive('хибна','000',['10','110','10','0','1','01','01']);
  Positive('істинна-нуль','0',['10','110','10','1','0','01','01']);
  Positive('істинна-один','1',['10','110','10','1','1','01','01']);
  Positive('друга-істинна','1',
    ['10','110','10','0','0','01','10','1','1','01','01']);
  Positive('першу-обрано','1',
    ['10','110','10','1','1','01','10','1','0','01','01']);
  Positive('дві-хибні','000',
    ['10','110','10','0','1','01','10','0','0','01','01']);
  Positive('вкладений-тест','0',
    ['10','110','10','10','101','1','1','01','0','01','01']);
  Positive('вкладений-пропуск','000',
    ['10','110','10','10','101','0','1','01','0','01','01']);
  Positive('вкладений-вираз-один','1',
    ['10','110','10','1','10','101','0','0','01','01','01']);
  Positive('вкладений-вираз-нуль','0',
    ['10','110','10','1','10','101','0','1','01','01','01']);
  Positive('обидва-вкладені-нуль','0',
    ['10','110','10','10','101','1','1','01',
     '10','101','1','0','01','01','01']);
  Positive('обидва-вкладені-один','1',
    ['10','110','10','10','101','0','0','01',
     '10','101','1','1','01','01','01']);
  Positive('вкладені-дві-гілки','1',
    ['10','110',
     '10','10','101','0','1','01','10','101','0','0','01','01',
     '10','10','101','1','1','01','10','101','1','1','01','01',
     '01']);
  Positive('друга-вкладена-обрана','0',
    ['10','110',
     '10','0','1','01',
     '10','10','101','1','1','01','10','101','0','1','01','01',
     '01']);
  Positive('перша-вкладена-обрана','1',
    ['10','110',
     '10','10','101','1','1','01','10','101','0','0','01','01',
     '10','1','0','01','01']);
  Positive('дві-вкладені-хибні','000',
    ['10','110',
     '10','10','101','0','1','01','0','01',
     '10','10','101','0','1','01','1','01','01']);

  { G6.239: третя впорядкована pinned D3:110 гілка дійсно
    компілюється як JZ/JMP з одним спільним машинним виходом.
    Програми — точні фізичні T5M слова, не український dispatch. }
  Positive('третя-обрана','1',
    ['10','110',
     '10','0','0','01','10','0','1','01',
     '10','1','1','01','01']);
  Positive('третя-вкладена','0',
    ['10','110',
     '10','0','1','01','10','0','0','01',
     '10','10','101','1','1','01',
          '10','101','1','0','01','01','01']);
  Positive('три-хибні','000',
    ['10','110',
     '10','0','0','01','10','0','1','01',
     '10','0','1','01','01']);
  { Шість machine CALLsite — дві вкладені D3:101 у кожній із
    трьох гілок; EQ не обчислюється у Pascal. }
  Positive('три-вкладені-виклики','1',
    ['10','110',
     '10','10','101','0','1','01','10','101','1','0','01','01',
     '10','10','101','0','1','01','10','101','0','0','01','01',
     '10','10','101','1','1','01','10','101','1','1','01','01',
     '01']);

  Negative('чотири-гілки',
    ['10','110','10','0','0','01','10','0','0','01',
     '10','0','0','01','10','1','1','01','01']);
  Negative('неправильна-голова',['10','101','10','1','0','01','01']);
  Negative('зайве-поле',['10','110','10','1','0','1','01','01']);
  Negative('D7-тест',['10','110','10','0010110','1','01','01']);
  Negative('D12-тест',['10','110','10','000000000000','1','01','01']);
  Negative('D12-вираз',['10','110','10','1','000000000000','01','01']);
  Negative('порожній-тест',['10','110','10','000','1','01','01']);
  Negative('два-корені',['10','110','01','0']);
  Negative('невірна-вкладеність',
    ['10','110','10','10','101','0','01','1','01','01']);
  Negative('хибна-вкладена-голова',
    ['10','110','10','10','111','0','0','01','1','01','01']);
  Negative('вкладений-D7',
    ['10','110','10','10','101','0010110','0','01','1','01','01']);
  Negative('вкладений-D12',
    ['10','110','10','1','10','101','0','000000000000','01','01','01']);
  Negative('пропущено-вираз',
    ['10','110','10','1','01','01']);
  Negative('порожній-атом',['000']);
  NegativeRaw('фальшивий-T5M',#$F3);
  NegativeRaw('порожній-байтовий','');
  NegativeRaw('текстова-проекція','(за-умовою (так ні))'+#10);
  Check((Passed=21) and (Rejected=17),
    'втрачено 21 позитивний або 17 негативних свідків');
  WriteLn('G6_122_OK ELF=17 NEG=17 CALL_SITES=',CallsTotal,
    ' PHYSICAL=T5M ENERGY=NOT_MEASURED');
end.
