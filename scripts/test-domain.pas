program test_domain;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain;
var F:TFileStream; S:RawByteString; Rows:TDomainTable; K:TDomainKey;
procedure Require(Ok:Boolean; const MessageText:String);
begin if not Ok then begin WriteLn(StdErr,'DOMAIN-FAIL ',MessageText); Halt(1); end; end;
begin
  F:=TFileStream.Create('external/sens/lib/domains/d3.lisp',fmOpenRead);
  try SetLength(S,F.Size); if F.Size>0 then F.ReadBuffer(S[1],F.Size);
  finally F.Free; end;
  LoadDomainTable(S,3,Rows);
  Require(Length(Rows)=8,'D3 must have eight exact coordinates');
  Require(UkrainianKey(Rows,'як-є',K),'missing Ukrainian quote surface');
  Require(SameKey(K,ExactKey('001')),'quote coordinate mismatch');
  Require(UkrainianKey(Rows,'за-умовою',K),'missing Ukrainian cond surface');
  Require(SameKey(K,ExactKey('110')),'cond coordinate mismatch');
  Require(not UkrainianKey(Rows,'quote',K),'English is not Ukrainian surface');
  Require(not SameKey(ExactKey('01'),ExactKey('001')),'width identity collapsed');
  Require(KeyBits(ExactKey('000'))='000','zero key loses width');
  WriteLn('DOMAIN-OK rows=8 width=3 uk=verified');
end.
