{ G6.176: Free Pascal twin; stdin/stdout are the same packed T5M ABI. }
{ Frame/Trits/Output are stack arrays (7/30/3 bytes); no heap object escapes.
  fpRead borrows fd 0; fpWrite borrows fd 1; the process owns no persistent state.
  Questions: Why are both padding spans checked? Why exact division only?
  Why is the result bounded to D12? Which layer supplies the callable D5 law? }
program quot_fpc;
{$mode objfpc}{$H+}
uses BaseUnix, SysUtils;
type TFrame = array[0..6] of Byte;
     TTrits = array[0..29] of Byte;
     TOutput = array[0..2] of Byte;

procedure Fail;
const MessageText: RawByteString = 'D12 quotient frame rejected' + #10;
begin
  if Length(MessageText) > 0 then fpWrite(2, MessageText[1], Length(MessageText));
  Halt(2);
end;

function DecodeSigned(const Digits: TTrits; Start: SizeInt): LongInt;
var I: SizeInt; V: LongWord;
begin
  V:=0;
  for I:=0 to 11 do begin
    if Digits[Start+I]>1 then Fail;
    V:=(V shl 1) or Digits[Start+I];
  end;
  if Digits[Start]=1 then Result:=LongInt(V)-4096 else Result:=LongInt(V);
end;

function PackResult(Value: LongInt; out Encoded: TOutput): Boolean;
var G,O,Digit,Index: SizeInt; V: LongWord;
begin
  Result:=False;
  if (Value < -2048) or (Value > 2047) then Exit;
  V:=LongWord(Value) and $FFF;
  for G:=0 to 2 do begin
    Encoded[G]:=0;
    for O:=0 to 4 do begin
      Index:=G*5+O;
      if Index<12 then Digit:=(V shr (11-Index)) and 1 else Digit:=2;
      Encoded[G]:=Encoded[G]*3+Digit;
    end;
    if Encoded[G]>=243 then Exit;
  end;
  Result:=True;
end;

var Frame:TFrame;Trits:TTrits;OutputBytes:TOutput;
    I,J,V,ReadCount,Left,Right,Quotient:LongInt;
begin
  FillChar(Frame,SizeOf(Frame),0);
  ReadCount:=fpRead(0,Frame[0],SizeOf(Frame));
  if ReadCount<>6 then Fail;
  for I:=0 to 5 do begin
    V:=Frame[I]; if V>=243 then Fail;
    for J:=4 downto 0 do begin Trits[I*5+J]:=V mod 3; V:=V div 3 end;
    if V<>0 then Fail;
  end;
  for I:=12 to 14 do if Trits[I]<>2 then Fail;
  for I:=27 to 29 do if Trits[I]<>2 then Fail;
  Left:=DecodeSigned(Trits,0); Right:=DecodeSigned(Trits,15);
  if (Right=0) or ((Left mod Right)<>0) then Fail;
  Quotient:=Left div Right;
  if not PackResult(Quotient,OutputBytes) then Fail;
  if fpWrite(1,OutputBytes[0],SizeOf(OutputBytes))<>SizeOf(OutputBytes) then Fail;
end.
