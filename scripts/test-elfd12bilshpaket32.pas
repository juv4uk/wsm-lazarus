{ G6.94 — тестові signed W12 числа тільки через чинний codec
  EncodeNumericDecimal. Кожна host .frame містить 32 пари ОКРЕМИХ
  трьохбайтових canonical packed D12 атомів — це НЕ .sens файл.
  Очікуваний W1 D1-результат — тестовий вектор, а НЕ новий закон:
  усі 16 різних пар додатково звіряються з pinned SENS REPL. }
program test_elfd12bilshpaket32;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
type TFixture=record
  LeftText,RightText,LeftBytes,RightBytes,ExpectedBytes:RawByteString;
end;
var Dir:String;Cases:array[0..15] of TFixture;
    Num:SizeInt;NoByte,YesByte,D7,Frame,Expected,Order,V:RawByteString;
    Words:TExactWords;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
procedure CaseOf(const L,R:RawByteString;IsGreater:Boolean);
var N:SizeInt;
begin
  N:=Num;
  if N>15 then raise Exception.Create('надто багато тестових D12 пар');
  Cases[N].LeftText:=L;Cases[N].RightText:=R;
  Cases[N].LeftBytes:=EncodeNumericDecimal(L,12);
  Cases[N].RightBytes:=EncodeNumericDecimal(R,12);
  if (Length(Cases[N].LeftBytes)<>3) or
     (Length(Cases[N].RightBytes)<>3) then
    raise Exception.Create('signed D12 не 3 байти');
  if IsGreater then Cases[N].ExpectedBytes:=YesByte
  else Cases[N].ExpectedBytes:=NoByte;
  WriteLn(N,#9,L,#9,R,#9,Ord(IsGreater));
  Inc(Num);
end;

procedure Batch(const Name:RawByteString;Shift,Stride:SizeInt);
var I,N:SizeInt;FrameBytes,AnswerBytes,Sequence:RawByteString;
begin
  FrameBytes:='';AnswerBytes:='';Sequence:='';
  for I:=0 to 31 do begin
    N:=(I*Stride+Shift) mod 16;
    FrameBytes:=FrameBytes+Cases[N].LeftBytes+Cases[N].RightBytes;
    AnswerBytes:=AnswerBytes+Cases[N].ExpectedBytes;
    Sequence:=Sequence+AnsiChar(Ord('A')+N);
  end;
  if (Length(FrameBytes)<>192) or (Length(AnswerBytes)<>32) or
     (Length(Sequence)<>32) then
    raise Exception.Create('пакет W12/W1 не повний');
  Save(String(Name)+'.frame',FrameBytes);
  Save(String(Name)+'.expected',AnswerBytes);
  Save(String(Name)+'.order',Sequence);
end;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);if not ForceDirectories(Dir) then Halt(2);
  SetLength(Words,1);
  Words[0]:='0';NoByte:=EncodeT5M(Words);
  Words[0]:='1';YesByte:=EncodeT5M(Words);
  if (Length(NoByte)<>1) or (Length(YesByte)<>1) then Halt(2);
  Num:=0;
  CaseOf('-2048','-2048',False);
  CaseOf('-2048','2047',False);
  CaseOf('2047','-2048',True);
  CaseOf('0','-1',True);
  CaseOf('-1','0',False);
  CaseOf('3','2',True);
  CaseOf('2','3',False);
  CaseOf('7','7',False);
  CaseOf('-1024','-1500',True);
  CaseOf('-1024','-1000',False);
  CaseOf('2047','2046',True);
  CaseOf('2046','2047',False);
  CaseOf('1','0',True);
  CaseOf('0','1',False);
  CaseOf('-7','-9',True);
  CaseOf('-9','-7',False);
  if Num<>16 then Halt(2);
  Batch('batch-a',3,5);
  Batch('batch-b',11,7);
  Frame:=Cases[0].LeftBytes+Cases[0].RightBytes;
  Save('empty.frame','');
  Save('one-byte.frame',Copy(Frame,1,1));
  V:='';
  while Length(V)<192 do V:=V+Frame;
  Frame:=Copy(V,1,192);
  Save('short191.frame',Copy(Frame,1,191));
  Save('short190.frame',Copy(Frame,1,190));
  Save('extra193.frame',Frame+#0);
  Save('extra194.frame',Frame+#0+#0);
  Save('ascii.frame',StringOfChar('0',192));
  V:=Frame;V[1]:=#$FF;Save('bad-first.frame',V);
  V:=Frame;V[93]:=#$FF;Save('bad-middle.frame',V);
  V:=Frame;V[192]:=#$FF;Save('bad-last.frame',V);
  V:=Frame;V[3]:=#$00;Save('bad-third-w2.frame',V);
  SetLength(Words,1);Words[0]:='0010110';D7:=EncodeT5M(Words);
  Save('d7-width.frame',D7+Copy(Frame,4,189));
  Save('ukr-text.frame','(більше? 3 2)');
  WriteLn(StdErr,'D12-BILSH-PAKET32-FIXTURES-OK cases=16 batches=2 negatives=13');
end.
