{ G1.10 — незмінний вузький reader + опційні широкі T5M D2 вузли.
  Фізична ширина ніколи не стверджує математичну семантику. }
program test_d2wide;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source;
var W:TExactWords; Doc:TD2Document; I,Negative:SizeInt;
    Physical:RawByteString; F:TFileStream;
procedure Require(Ok:Boolean;const Why:String);
begin
  if not Ok then begin WriteLn(StdErr,'D2-WIDE-FAIL ',Why); Halt(1); end;
end;
function WordsOf(const A:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(A));
  for J:=0 to High(A) do Result[J]:=A[J];
end;
function RepeatBit(Count:SizeInt; Bit:AnsiChar):RawByteString;
begin
  SetLength(Result,Count);
  if Count>0 then FillChar(Result[1],Count,Ord(Bit));
end;
procedure Bad(const A:TExactWords;At:SizeInt;const Why:String);
var Failure:Boolean; T:TD2Document;
begin
  Failure:=False; T:=nil;
  try T:=ParseD2WordsWide(A);
  except on E:ED2SourceError do Failure:=E.WordIndex=At; end;
  T.Free;
  Require(Failure,'expected fail '+Why);
  Inc(Negative);
end;
begin
  W:=WordsOf(['10',RepeatBit(12,'0'),'10',RepeatBit(24,'0'),
     RepeatBit(48,'1'),RepeatBit(96,'0'),RepeatBit(192,'1'),
     '01','01','0']);
  Physical:=EncodeT5M(W);
  Doc:=ReadD2T5MWide(Physical);
  try
    Require(Length(Doc.Roots)=2,'physical roots');
    Require((Doc.Roots[0].Kind=dkList) and
      (Length(Doc.Roots[0].Children)=2),'outer list');
    Require((Doc.Roots[0].Children[0].WordIndex=2) and
      (Doc.Roots[0].Children[0].Width=12) and
      (Doc.Roots[0].Children[0].Bits=RepeatBit(12,'0')),
      'W12 preserved incl leading zeros');
    Require(Doc.Roots[0].Children[1].Kind=dkList,'inner D2 list');
    for I:=0 to 3 do begin
      Require(Doc.Roots[0].Children[1].Children[I].WordIndex=4+I,
        'wide nested physical index');
      Require(Doc.Roots[0].Children[1].Children[I].Width=
        (24 shl I),'wide nested physical width');
      Require(Doc.Roots[0].Children[1].Children[I].Bits=
        W[3+I],'wide nested bits unchanged');
    end;
    Require((Doc.Roots[1].Kind=dkIdentity) and
      (Doc.Roots[1].WordIndex=10) and
      (Doc.Roots[1].Width=1) and (Doc.Roots[1].Bits='0'),
      'D1:0 remains separate from D3:000');
  finally Doc.Free; end;
  { Legacy API remains byte-for-byte and failure-compatible: W12 denied. }
  Bad(WordsOf([RepeatBit(193,'0')]),1,'193-bit quota');
  Bad(WordsOf(['10',RepeatBit(193,'1'),'01']),2,'nested quota');
  Bad(WordsOf(['10',RepeatBit(12,'0')]),3,'D2 EOF');
  Bad(WordsOf(['10',RepeatBit(24,'0'),'11','01']),4,'D2 dot tail');
  Bad(WordsOf(['10',RepeatBit(96,'0'),'01','01']),4,'D2 unmatched close');
  Bad(WordsOf(['10',RepeatBit(12,'0'),'2','01']),3,'not binary');
  Bad(WordsOf(['']),1,'empty word');
  Bad(WordsOf([]),1,'empty source');
  Negative:=8;
  Doc:=nil;
  try Doc:=ParseD2Words(WordsOf([RepeatBit(12,'0')]));
  except on E:ED2SourceError do Inc(Negative); end;
  Doc.Free;
  Require(Negative=9,'legacy reader did not reject W12');
  Doc:=nil;
  try Doc:=ParseD2Words(WordsOf([RepeatBit(10,'1')]));
  except on E:ED2SourceError do Inc(Negative); end;
  Doc.Free;
  Require(Negative=10,'legacy reader did not reject W10');
  { Опційний reader допускає W10/W13 ЛИШЕ як механічну структуру.
    Це не доказ D10 callable або неіснуючого числового D13. }
  Doc:=ParseD2WordsWide(WordsOf([RepeatBit(13,'0')]));
  try Require((Doc.Roots[0].Width=13) and
    (Doc.Roots[0].Bits=RepeatBit(13,'0')),'W13 opaque');
  finally Doc.Free; end;
  Doc:=nil;
  try Doc:=ReadD2T5MWide(#243);
  except on E:ET5MError do Inc(Negative); end;
  Doc.Free;
  Require(Negative=11,'T5M invalid 243 not rejected');

  { Реальний pinned D24 witness читаємо ФІЗИЧНО, не з назви чи .lisp. }
  if ParamCount=1 then begin
    F:=TFileStream.Create(ParamStr(1),fmOpenRead or fmShareDenyWrite);
    try
      Require((F.Size>0) and (F.Size<=MAX_T5M_FILE_BYTES),
        'pinned numeric corpus physical size');
      SetLength(Physical,SizeInt(F.Size));
      F.ReadBuffer(Physical[1],Length(Physical));
    finally F.Free; end;
    DecodeT5M(Physical,W);
    Require((Length(W)=11) and (Length(W[6])=24) and
      (Length(W[8])=24) and (W[6]=RepeatBit(23,'0')+'1') and
      (W[8]=RepeatBit(22,'0')+'11'),'pinned real D24 bits');
    Require(EncodeT5M(W)=Physical,'pinned T5M byte-exact');
    Doc:=ReadD2T5MWide(Physical);
    try
      Require((Length(Doc.Roots)=1) and
        (Doc.Roots[0].Kind=dkList) and
        (Length(Doc.Roots[0].Children)=2),'pinned D2 list structure');
      Require(Doc.Roots[0].Children[1].Kind=dkList,
        'pinned nested D2 expression');
      Require((Doc.Roots[0].Children[1].Children[1].Width=24) and
        (Doc.Roots[0].Children[1].Children[1].WordIndex=7) and
        (Doc.Roots[0].Children[1].Children[2].WordIndex=9),
        'pinned numeric physical positions');
    finally Doc.Free; end;
  end;
  WriteLn('ШИРОКИЙ-D2-ГАРАЗД ширини=12,24,48,96,192 ',
    'негативні=',Negative,' контракт=лише-pinned ');
  WriteLn('ШИРОКИЙ-D2-МЕЖА дані=непрозорі число=не-виведено ',
    'вузький-reader=незмінний');
end.
