{ G6.107 — машинний CALL/RET FPC, GNU as, real ELF64 D3:101 oracle.
  Всі джерела канонічно кодуються wsm.t5m без україномовного dispatch.
  Типи: TX64Code — managed host bytes, Phys — owned canonical .sens,
  Image — owned ELF64, LowerPinnedD3Eq — pinned admission + ExactIR.
  Питання: 1) Який фізичний байт повертає D1:1?
  2) Чому signed rel32 backward мають FF high bytes?
  3) Як fail-closed зберігає Code.Bytes?
  4) Чому для кожного .sens окремо запускається pinned SENS?
  5) Чому 4 ELF не доводять рекурсивний APPLY? }
program test_ircallwriter;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64call,wsm.ircallwriter,
  wsm.ircallabi,wsm.elfgeometry,wsm.t5m;

var DirectoryName:String;GoodCount,BadCount,HostBad:SizeInt;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;
procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('CALL-КОДЕР-ПРОВАЛ: '+Why);
end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(DirectoryName+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
procedure Positive(const Name:String;L,R:Byte);
var Source,Image,Old,Expected:RawByteString;Word:TExactWords;
    Geom:TELFGeometry;
begin
  Check((L<=1) and (R<=1),'не D1 тестова пара');
  Source:=EncodeT5M(W(['10','101',
    AnsiChar(Ord('0')+L),AnsiChar(Ord('0')+R),'01']));
  Image:=BuildPhysicalD3CallELF(Source,'external/sens');
  Old:=BuildPinnedD1EqCallELF(Source,'external/sens');
  Check(Image=Old,Name+': shared CALL emitter не дав доведений ELF64 ABI');
  Check(Image=BuildPhysicalD3CallELF(Source,'external/sens'),
    Name+': змінний ELF для однакового канонічного .sens');
  VerifySENSELF64(Image,Geom);
  Check((Geom.Kind=3) and (Geom.Entry=120) and (Geom.FileBytes=Length(Image)),
    Name+': пошкоджена ELF геометрія');
  SetLength(Word,1);
  if L=R then Word[0]:='1' else Word[0]:='0';
  Expected:=EncodeT5M(Word);
  Check(Length(Expected)=1,Name+': D1 вихід не packed one byte');
  Save(Name+'.sens',Source);
  Save(Name+'.elf',Image);
  Save(Name+'.expected.sens',Expected);
  Inc(GoodCount);
end;

procedure NegativeRaw(const Name:String;const Physical:RawByteString);
var Image:RawByteString;Failed:Boolean; ErrorText:String;
begin
  Failed:=False;Image:='';ErrorText:='';
  try Image:=BuildPhysicalD3CallELF(Physical,'external/sens');
  except on E:Exception do begin Failed:=True;ErrorText:=E.Message end end;
  Check(Failed and (Image='') and (Length(ErrorText)>3),
    Name+': неправильний або неатомарний reject');
  Inc(BadCount);
end;
procedure Negative(const Name:String;const Parts:array of RawByteString);
begin NegativeRaw(Name,EncodeT5M(W(Parts))) end;

procedure HostReject(Kind:SizeInt);
var C:TX64Code;Before:RawByteString;Failed:Boolean;Fix:SizeInt;
begin
  X64Reset(C);
  X64EmitLocalCall(C,Fix);
  C.Bytes:=C.Bytes+#$90;
  case Kind of
    1:C.Bytes[1]:=#$90;           { чужий opcode }
    2:C.Bytes[3]:=#$40;           { nonempty placeholder }
    3:C.Bytes:=#$90;              { занадто короткий fixup }
    4:C.Bytes:=StringOfChar(AnsiChar($90),256); { квота }
    5:C.Bytes:=#$E8#0#0#0#0;    { target outside }
    6:;                          { invalid target negative }
    7:;                          { invalid offset }
    8:;                          { target next instruction => delta=0 }
    9:;                          { wrong offset 5 }
    10:;                         { patch twice }
    11:;                         { RET overflow }
    12:;                         { CALL overflow }
    else raise Exception.Create('невідомий host negative');
  end;
  if Kind=10 then X64PatchLocalCall(C,Fix,0);
  Before:=C.Bytes;
  Failed:=False;
  try
    case Kind of
      1,2,3,4:X64PatchLocalCall(C,Fix,0);
      5:X64PatchLocalCall(C,Fix,5);
      6:X64PatchLocalCall(C,Fix,-1);
      7:X64PatchLocalCall(C,-1,0);
      8:X64PatchLocalCall(C,Fix,5);
      9:X64PatchLocalCall(C,5,0);
      10:X64PatchLocalCall(C,Fix,0);
      11:begin
        C.Bytes:=StringOfChar(AnsiChar($90),256);
        Before:=C.Bytes;
        X64Return(C)
      end;
      12:begin
        C.Bytes:=StringOfChar(AnsiChar($90),256);
        Before:=C.Bytes;
        X64EmitLocalCall(C,Fix)
      end;
    end;
  except on E:EX64CodeError do Failed:=True end;
  Check(Failed and (C.Bytes=Before),
    'host негатив порушив атомарність '+IntToStr(Kind));
  Inc(HostBad);
  X64Reset(C);
  X64EmitLocalCall(C,Fix);
  C.Bytes:=C.Bytes+#$90;
  X64PatchLocalCall(C,Fix,0);
  Check(C.Bytes=#$E8#$FB#$FF#$FF#$FF#$90,
    'host CALL не відновився після негативу');
end;

procedure HostGolden;
var C:TX64Code;First,Second:SizeInt;
    Machine:RawByteString;
begin
  X64Reset(C);
  X64EmitLocalCall(C,First);
  Check(First=1,'disp32 має бути 0-based +1');
  C.Bytes:=C.Bytes+#$90;
  X64Return(C);
  X64PatchLocalCall(C,First,6);
  Check(C.Bytes=#$E8#$01#0#0#0#$90#$C3,
    'точний CALL forward +1');
  C.Bytes:=C.Bytes+#$90;
  X64EmitLocalCall(C,Second);
  Check(Second=9,'CALL backward offset');
  X64Return(C);
  X64PatchLocalCall(C,Second,0);
  Machine:=C.Bytes;
  Check(Machine=#$E8#$01#0#0#0#$90#$C3#$90+
    #$E8#$F3#$FF#$FF#$FF#$C3,
    'CALL forward/back + RET exact host bytes');
  Save('call-matrix.fpc.bin',Machine);
  Save('call-matrix.s','.intel_syntax noprefix'+#10+
    '.text'+#10+'.global _start'+#10+'_start:'+#10+
    'call forward'+#10+'nop'+#10+'forward:'+#10+
    'ret'+#10+'nop'+#10+'call _start'+#10+'ret'+#10);
end;

var I:SizeInt;
begin
  Check((ParamCount=1) and DirectoryExists(ParamStr(1)),
    'потрібен реальний каталог свідків');
  DirectoryName:=ParamStr(1);
  GoodCount:=0;BadCount:=0;HostBad:=0;
  HostGolden;
  for I:=1 to 12 do HostReject(I);

  Positive('рівність-00',0,0);
  Positive('рівність-01',0,1);
  Positive('рівність-10',1,0);
  Positive('рівність-11',1,1);

  Negative('інша-голова',['10','110','0','0','01']);
  Negative('неповний-виклик',['10','101','0','01']);
  Negative('три-аргументи',['10','101','0','0','1','01']);
  Negative('ліва-порожнеча',['10','101','000','0','01']);
  Negative('права-порожнеча',['10','101','1','000','01']);
  Negative('ліва-D7',['10','101','0010110','0','01']);
  Negative('права-D12',['10','101','0','000000000000','01']);
  Negative('інша-ширина',['10','101','10','0','01']);
  Negative('два-корені',['10','101','1','1','01','0']);
  Negative('крапкова-пара',['10','101','11','0','1','01']);
  NegativeRaw('битий-T5M',#$F3);
  NegativeRaw('порожній-T5M','');
  NegativeRaw('підроблений-текст.lisp',
    '(тотожне? так ні)'+#10);

  Check((GoodCount=4) and (BadCount=13) and (HostBad=12),
    'втрачено positive/negative свідок');
  WriteLn('G6_107_OK ELF=',GoodCount,' PHYS_NEG=',BadCount,
    ' HOST_NEG=',HostBad);
  WriteLn('CALL-КОДЕР-ГОТОВО ELF=',GoodCount,
    ' SENS-негативи=',BadCount,' host-негативи=',HostBad,
    ' GNU-as=зовнішній pinned-SENS=зовнішній energy=NOT-MEASURED');
end.
