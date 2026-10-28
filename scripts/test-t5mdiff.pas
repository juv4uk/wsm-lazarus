{ G1.12: позитивні, негативні й відновлювальні фізичні перевірки. }
program test_t5mdiff;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.t5mdiff;
var C:TPhysicalComparison; A,B,D,Shorter,Malformed:RawByteString;
    Count:Integer;

function Pack(const S:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(S));
  for I:=0 to High(S) do W[I]:=S[I];
  Result:=EncodeT5M(W);
end;
procedure Need(Ok:Boolean;const Reason:String);
begin
  Inc(Count);
  if not Ok then raise Exception.Create('Т5М-РІЗНИЦЯ-ПОМИЛКА: '+Reason);
end;
procedure Bad(const L,R:RawByteString);
var Failed:Boolean;
begin
  C.Kind:=pdEqual; Failed:=False;
  try ComparePhysicalWords(L,R,C);
  except on E:Exception do Failed:=True; end;
  Need(Failed,'хибні фізичні байти прийнято');
  Need(C.Kind=pdNotChecked,'після відмови залишився результат');
end;
begin
  Count:=0;
  A:=Pack(['0','000000000001','111']);
  B:=Pack(['0','000000000001','110']);
  D:=Pack(['0','0000000000001','111']);
  Shorter:=Pack(['0','000000000001']);
  ComparePhysicalWords(A,A,C);
  Need((C.Kind=pdEqual) and (C.LeftCount=3) and (C.RightCount=3),
    'ідентичність T5M');
  ComparePhysicalWords(A,B,C);
  Need((C.Kind=pdBits) and (C.WordIndex=3) and (C.BitIndex=3),
    'перший відмінний біт');
  Need((C.LeftSpan.TritStart=15) and (C.LeftSpan.TritEnd=18) and
       (C.LeftSpan.ByteStart=3) and (C.LeftSpan.ByteEnd=4),
    'точна адреса відмінного слова');
  ComparePhysicalWords(A,D,C);
  Need((C.Kind=pdWidth) and (C.WordIndex=2) and
       (C.LeftWidth=12) and (C.RightWidth=13) and
       (C.LeftSpan.TritStart=2) and (C.RightSpan.TritStart=2),
    'провідні нулі й ширина D12+');
  ComparePhysicalWords(A,Shorter,C);
  Need((C.Kind=pdWordCount) and (C.WordIndex=3) and
       (not C.LeftSpan.IsEOF) and C.RightSpan.IsEOF and
       (C.RightWidth=0), 'EOF справа');
  ComparePhysicalWords(Shorter,A,C);
  Need((C.Kind=pdWordCount) and C.LeftSpan.IsEOF and
       (C.RightWidth=3), 'EOF зліва');
  Malformed:=A+AnsiChar(243);
  Bad(Malformed,A); Bad(A,Malformed);
  Bad('',A); Bad(A,'');
  Bad(Pack(['0'])+AnsiChar(255),B);
  ComparePhysicalWords(A,A,C);
  Need(C.Kind=pdEqual,'відновлення після помилки');
  WriteLn('Т5М-РІЗНИЦЯ-ГАРАЗД перевірок=',Count,
    ' біти=точно ширина=D12+ адреса=трит/байт',
    ' помилки=атомарні семантика=НЕ-ПЕРЕВІРЕНО');
end.
