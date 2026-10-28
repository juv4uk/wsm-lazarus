{ Нативні фізичні перевірки обмеженого двійкового допуску.
  Жодна українська чи англійська назва не маршрутизує семантику. }
program test_t5madmission;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.t5madmission;

procedure Check(Ok: Boolean; const Why: String);
begin
  if not Ok then begin
    WriteLn(StdErr,'ДОПУСК-Т5М-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

function WordsOf(const A: array of RawByteString): TExactWords;
var I: SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

function FromPhysical(const Physical: RawByteString): TD2Document;
var S: TMemoryStream;
begin
  S:=TMemoryStream.Create;
  try
    if Length(Physical)>0 then S.WriteBuffer(Physical[1],Length(Physical));
    S.Position:=0;
    Result:=ReadCheckedD2Stream(S);
  finally S.Free; end;
end;

procedure SameNode(A,B: TD2Node);
var I: SizeInt;
begin
  Check((A<>nil) and (B<>nil),'вузол відсутній');
  Check((A.Kind=B.Kind) and (A.WordIndex=B.WordIndex) and
        (A.Width=B.Width) and (A.Bits=B.Bits),
        'втрата ширини, бітів або джерельного індексу');
  Check(Length(A.Children)=Length(B.Children),'кількість нащадків');
  for I:=0 to High(A.Children) do SameNode(A.Children[I],B.Children[I]);
end;

procedure CompareValid(const Input: array of RawByteString);
var A,B: TD2Document; Data: RawByteString; I:SizeInt;
begin
  Data:=EncodeT5M(WordsOf(Input));
  A:=ReadD2T5M(Data);
  B:=FromPhysical(Data);
  try
    Check(Length(A.Roots)=Length(B.Roots),'кількість коренів');
    for I:=0 to High(A.Roots) do SameNode(A.Roots[I],B.Roots[I]);
  finally A.Free; B.Free; end;
end;

procedure RejectPhysical(const Physical: RawByteString; const Why: String);
var D: TD2Document; Rejected: Boolean;
begin
  D:=nil;
  Rejected:=False;
  try
    D:=FromPhysical(Physical);
  except
    on E:ET5MAdmissionError do Rejected:=True;
    on E:ET5MError do Rejected:=True;
    on E:ED2SourceError do Rejected:=True;
  end;
  D.Free;
  Check(Rejected,Why+' прийнято');
end;

procedure RejectWords(const Words: array of RawByteString; const Why: String);
begin
  RejectPhysical(EncodeT5M(WordsOf(Words)),Why);
end;

var
  S: TMemoryStream;
  D: TD2Document;
  W: TExactWords;
  I: SizeInt;
begin
  CompareValid(['10','111','00','1','000','01']);
  CompareValid(['10','1','11','0','01']);
  CompareValid(['0','00','1']);
  CompareValid(['101010101']);
  CompareValid(['000000000']);
  D:=FromPhysical(EncodeT5M(WordsOf(['10','111','1','000','01'])));
  try
    Check(Length(D.Roots)=1,'одна форма');
    Check(D.Roots[0].Kind=dkList,'фізичний відкритий D2 список');
    Check(Length(D.Roots[0].Children)=3,'три елементи');
    Check((D.Roots[0].Children[0].Bits='111') and
      (D.Roots[0].Children[0].Width=3),'точна D3-координата');
    Check((D.Roots[0].Children[1].Bits='1') and
      (D.Roots[0].Children[1].Width=1),'точна D1-координата');
    Check(D.Roots[0].Children[2].Kind=dkEmpty,'D3:000 окремо від D1:0');
  finally D.Free; end;

  RejectPhysical('','порожній потік');
  RejectPhysical(#243,'заборонений байт 243');
  RejectPhysical(#255,'заборонений байт 255');
  RejectPhysical(#242,'лише заповнення');
  RejectPhysical(#162,'початковий роздільник');
  RejectPhysical(#72,'подвійний роздільник');
  RejectPhysical(#80#0,'внутрішнє повторне заповнення');
  RejectWords(['0000000000'],'слово W10 поза D2');
  RejectWords(['00000000000'],'слово W11 поза D2');
  RejectWords(['01'],'неприпустиме закриття D2');
  RejectWords(['10','1'],'незавершений D2 список');
  RejectWords(['10','11','1','01'],'крапка D2 без голови');

  { 100001 слів W1: фізичний T5M допустимий, але D2 бюджету недостатньо.
    Відхилити ДО матеріалізації сотні тисяч вузлів AST. }
  SetLength(W,MaxD2Words+1);
  for I:=0 to High(W) do W[I]:='1';
  RejectPhysical(EncodeT5M(W),'перевищено ліміт кількості слів');

  S:=TMemoryStream.Create;
  try
    D:=nil;
    try D:=ReadCheckedD2Stream(nil);
    except on E:ET5MAdmissionError do begin end; end;
    Check(D=nil,'відсутній потік прийнято');
  finally S.Free; end;

  WriteLn('ДВІЙКОВИЙ-ДОПУСК-ГАРАЗД: FPC=справжній T5M=чинний ',
    'D2=чинний W1–W9=строго слів=обмежено AST=без-часткового ',
    'українська=проєкція семантика=не-доведено');
end.
