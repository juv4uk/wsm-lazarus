program test_source;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.source;

procedure Require(Ok: Boolean; const Why: String);
begin
  if not Ok then begin
    WriteLn(StdErr,'SOURCE-FAIL ',Why); Halt(1);
  end;
end;

procedure MustFail(const LabelText: String; const Input: RawByteString);
var Failed: Boolean; D: TSourceDocument;
begin
  Failed := False;
  try D := ReadUkrainianProjection(Input);
  except on E: ESourceError do Failed := True; end;
  Require(Failed,'accepted invalid source: '+LabelText);
end;

var
  D: TSourceDocument;
  Input, Core: RawByteString;
  F: TFileStream;
  I, Opened, Closed: SizeInt;
begin
  Input := '(так' + #10 + '  (як-є "текст") ; коментар (' + #10 + '  ні)';
  D := ReadUkrainianProjection(Input);
  Require(D.FormCount=1,'single nested form');
  Require(D.ByteCount=Length(Input),'physical byte count');
  Require(Length(D.Tokens)=8,'comments/string not isolated structurally');
  Require(D.Tokens[0].Kind=skOpen,'first token is opening delimiter');
  Require(D.Tokens[1].Raw='так','Ukrainian UTF-8 atom bytes changed');
  Require(D.Tokens[2].Kind=skOpen,'nested opening delimiter missing');
  Require(D.Tokens[3].Raw='як-є','nested Ukrainian atom changed');
  Require(D.Tokens[4].Kind=skString,'quoted text not protected');
  Require(D.Tokens[4].Raw='"текст"','quoted original bytes changed');
  Require(D.Tokens[5].Kind=skClose,'nested closing delimiter missing');
  Require(D.Tokens[6].Raw='ні','third line atom not captured');
  Require(D.Tokens[7].Kind=skClose,'outer close missing');

  D := ReadUkrainianProjection('(так)' + #13#10 + '(ні)');
  Require(D.FormCount=2,'two top-level forms expected');
  Require(Length(D.Tokens)=6,'two lists must have six tokens');
  Require(D.Tokens[3].Line=2,'CRLF line counter double counted');
  Require(D.Tokens[3].Column=1,'CRLF column reset wrong');
  Require(D.Tokens[3].ByteOffset=10,'CRLF byte offsets wrong');

  D := ReadUkrainianProjection('(перше . (решта))');
  Require(D.FormCount=1,'dotted pair form count');
  Require(Length(D.Tokens)=7,'dotted pair token count');
  Require(D.Tokens[2].Kind=skDot,'D2 dot marker not parsed');
  D := ReadUkrainianProjection('(); коментар' + #10 + '()');
  Require(D.FormCount=2,'empty lists are forms');
  D := ReadUkrainianProjection(' "слово' + #92 + '" з пробілом" ');
  Require(D.FormCount=1,'quoted escaped string atomized');
  Require(D.Tokens[0].Kind=skString,'escaped quote is inside string');

  MustFail('unexpected close',')');
  MustFail('unterminated list','(так');
  MustFail('unterminated string','(так "ні)');
  MustFail('dangling escape','"' + #92);
  MustFail('empty dotted head','(. так)');
  MustFail('missing dotted tail','(так .)');
  MustFail('second dotted tail','(так . ні так)');
  MustFail('duplicate dot','(так . ні . друге)');
  MustFail('dot outside list','.');
  MustFail('stray NUL','(так)' + #0);
  MustFail('stray ASCII control',#31);
  MustFail('overlong UTF8',#192#175);
  MustFail('truncated UTF8',#226#130);
  MustFail('lone continuation',#128);
  MustFail('UTF8 surrogate',#237#160#128);
  MustFail('UTF8 BOM',#239#187#191 + '(так)');
  MustFail('Unicode outside U+10FFFF',#244#144#128#128);

  F := TFileStream.Create('external/sens/lib/core4.lisp',fmOpenRead);
  try
    Require((F.Size>0) and (F.Size<=64*1024*1024),'pinned Core4 unavailable or too large');
    SetLength(Core,F.Size);
    F.ReadBuffer(Core[1],Length(Core));
  finally F.Free; end;
  D := ReadUkrainianProjection(Core);
  Require(D.FormCount>1,'pinned Core4 contains no readable forms');
  Require(D.ByteCount=Length(Core),'pinned Core4 byte count mismatch');
  Opened := 0; Closed := 0;
  for I:=0 to High(D.Tokens) do begin
    if D.Tokens[I].Kind=skOpen then Inc(Opened)
    else if D.Tokens[I].Kind=skClose then Inc(Closed);
    Require((D.Tokens[I].Line>0) and (D.Tokens[I].Column>0),
            'missing Core4 source position');
  end;
  Require(Opened=Closed,'pinned Core4 parentheses unbalanced');
  WriteLn('SOURCE-OK utf8=validated framing=D2 dots=checked core4-syntax=accepted forms=',D.FormCount,
          ' core4-execution=NOT_PROVED binary-sens-roundtrip=NOT_PROVED');
end.
