program test_domain;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain;
var F:TFileStream; S:RawByteString; Rows:TDomainTable; K:TDomainKey; Row:TDomainRow; W:Integer; Rejected:Boolean;
procedure Require(Ok:Boolean; const MessageText:String);
begin if not Ok then begin WriteLn(StdErr,'DOMAIN-FAIL ',MessageText); Halt(1); end; end;
begin
  for W:=1 to 3 do begin
  F:=TFileStream.Create('external/sens/lib/domains/d'+IntToStr(W)+'.lisp',fmOpenRead);
  try SetLength(S,F.Size); if F.Size>0 then F.ReadBuffer(S[1],F.Size);
  finally F.Free; end;
  LoadDomainTable(S,W,Rows);
  Require(Length(Rows)=(1 shl W),'domain table is incomplete');
  end;
  LoadDomainTable(S,3,Rows);
  Require(Length(Rows)=8,'D3 must have eight exact coordinates');
  Require(UkrainianKey(Rows,'як-є',K),'missing Ukrainian quote surface');
  Require(SameKey(K,ExactKey('001')),'quote coordinate mismatch');
  Require(DomainRowByKey(Rows,ExactKey('001'),Row),'domain key not found');
  Require(Row.Ukrainian='як-є','reverse lookup wrong surface');
  Require(not DomainRowByKey(Rows,ExactKey('0001'),Row),'wrong-width lookup matched');
  Require(UkrainianKey(Rows,'за-умовою',K),'missing Ukrainian cond surface');
  Require(SameKey(K,ExactKey('110')),'cond coordinate mismatch');
  Require(not UkrainianKey(Rows,'quote',K),'English is not Ukrainian surface');
  Require(not SameKey(ExactKey('01'),ExactKey('001')),'width identity collapsed');
  Require(KeyBits(ExactKey('000'))='000','zero key loses width');
  Rejected:=False;
  try K:=ExactKey('00X'); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'nonbinary coordinate accepted');
  Rejected:=False;
  try K:=ExactKey(''); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'empty coordinate accepted');
  Rejected:=False;
  try LoadDomainTable('(000 (ук немає))',3,Rows); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'incomplete table accepted');
  Require(not SameKey(ExactKey('0'),ExactKey('00')),'D1/D2 key collision');
  Require(not SameKey(ExactKey('00'),ExactKey('000')),'D2/D3 key collision');
  WriteLn('DOMAIN-OK D1-D3 exact-width uk=verified');
end.
