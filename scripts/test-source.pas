program test_source;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.source;

var D: TSourceDocument; F: TFileStream; S: RawByteString;
    Nested: RawByteString; I: Integer; Caught: Boolean;

procedure Check(Ok: Boolean; const MessageText: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'SOURCE-FAIL ', MessageText);
    Halt(1);
  end;
end;

procedure Reject(const Value: RawByteString; const LabelText: String);
var R: TSourceDocument;
begin
  Caught := False;
  R := nil;
  try
    R := ReadUkrainianSource(Value);
  except
    on E: ESourceError do begin
      Caught := True;
      Check(E.ByteOffset >= 1, LabelText + ' lacks byte offset');
      Check(E.Line >= 1, LabelText + ' lacks line');
      Check(E.ByteColumn >= 1, LabelText + ' lacks byte column');
    end;
  end;
  R.Free;
  Check(Caught, LabelText + ' accepted');
end;


{ Лише UTF-8 людська проєкція: байти «і» непрозорі для reader.
  Вузли рахуємо фізично, без приписування доменів чи функцій. }
function FlatUkrainian(Count: SizeInt): RawByteString;
var J, P: SizeInt;
begin
  SetLength(Result, Count*3);
  for J := 0 to Count-1 do begin
    P := J*3+1;
    Result[P] := #$D1;
    Result[P+1] := #$96;
    Result[P+2] := ' ';
  end;
end;

function WideUkrainian(Count: SizeInt): RawByteString;
begin
  Result := '(' + FlatUkrainian(Count) + ')';
end;

procedure CheckNodeBoundary;
const NodeLimit = 65536; { фізична квота reader, не домен SENS }
var
  R: TSourceDocument;
  ErrorSeen: Boolean;
begin
  { Саме 65536 коренів; публічні Forms не мають резервних nil-слотів. }
  R := ReadUkrainianSource(FlatUkrainian(NodeLimit));
  try
    Check(Length(R.Forms)=NodeLimit, 'top-level source node boundary');
    Check(R.Forms[NodeLimit-1].Text=#$D1#$96, 'last UTF-8 atom changed');
    Check(R.Forms[NodeLimit-1].ByteOffset=3*(NodeLimit-1)+1,
      'last node physical byte position changed');
  finally R.Free; end;

  { Один корінь і 65535 дочірніх вузлів. }
  R := ReadUkrainianSource(WideUkrainian(NodeLimit-1));
  try
    Check(Length(R.Forms)=1, 'wide list root count');
    Check(Length(R.Forms[0].Children)=NodeLimit-1,
      'wide list child count includes capacity padding');
    Check(R.Forms[0].Children[NodeLimit-2].Text=#$D1#$96,
      'wide list last atom changed');
  finally R.Free; end;

  ErrorSeen := False;
  try
    R := ReadUkrainianSource(FlatUkrainian(NodeLimit)+#10+#$D1#$96);
    R.Free;
  except on E:ESourceError do begin
    ErrorSeen := (Pos('ліміт вузлів',E.Message)>0) and
      (E.ByteOffset=3*NodeLimit+2) and
      (E.Line=2) and (E.ByteColumn=1);
  end; end;
  Check(ErrorSeen, '65537-th flat node not rejected at exact line/byte');

  ErrorSeen := False;
  try
    R := ReadUkrainianSource(WideUkrainian(NodeLimit));
    R.Free;
  except on E:ESourceError do begin
    ErrorSeen := (Pos('ліміт вузлів',E.Message)>0) and
      (E.ByteOffset=3*NodeLimit-1) and
      (E.Line=1) and (E.ByteColumn=3*NodeLimit-1);
  end; end;
  Check(ErrorSeen, '65537-th nested node not rejected at exact byte');

  R := ReadUkrainianSource('(ні (так))');
  try
    Check((Length(R.Forms)=1) and
      (Length(R.Forms[0].Children)=2) and
      (Length(R.Forms[0].Children[1].Children)=1),
      'failed large AST parse poisoned next read');
  finally R.Free; end;
end;

begin
  D := ReadUkrainianSource(
    '; коментар із (дужками)' + #10 +
    '(визначити назва "рядок; (дужки)" (функція (х) х))' + #13#10 +
    '(так)');
  try
    Check(Length(D.Forms) = 2, 'multiple top-level forms');
    Check(D.Forms[0].Kind = skList, 'first root is list');
    Check(D.Forms[0].Line = 2, 'comment line tracking');
    Check(Length(D.Forms[0].Children) = 4, 'first root arity');
    Check(D.Forms[0].Children[0].Text = 'визначити', 'opaque exact atom');
    Check(D.Forms[0].Children[2].Kind = skString, 'string kind');
    Check(D.Forms[0].Children[2].Text = '"рядок; (дужки)"',
          'string bytes retained including quotes and semicolon');
    Check(D.Forms[0].Children[3].Kind = skList, 'nested list');
    Check(D.Forms[1].Line = 3, 'CRLF counts as one line');
    Check(D.Forms[1].ByteColumn = 1, 'CRLF byte column');
    Check(D.Forms[1].Children[0].Text = 'так', 'second exact atom');
  finally
    D.Free;
  end;

  D := ReadUkrainianSource('() (()) "а\"б"');
  try
    Check(Length(D.Forms) = 3, 'empty-list structure plus string');
    Check(Length(D.Forms[0].Children) = 0, 'empty list preserved');
    Check(Length(D.Forms[1].Children) = 1, 'nested empty list preserved');
    Check(D.Forms[2].Text = '"а\"б"', 'escaped quote retained');
  finally
    D.Free;
  end;

  D := ReadUkrainianSource(';' + #10 + '(ні)');
  try
    Check(D.Forms[0].ByteOffset = 3, 'exact source byte offset');
    Check(D.Forms[0].Line = 2, 'leading blank line');
  finally
    D.Free;
  end;

  Reject(')', 'extra close');
  Reject('(так', 'unclosed list');
  Reject('((так)', 'outer list unclosed');
  Reject('"без кінця', 'unclosed string');
  Reject('"escape' + '\', 'unfinished string escape');
  Reject('а' + #0 + 'б', 'embedded NUL');
  Reject('а' + #1 + 'б', 'ASCII control');
  Reject(#$C0#$AF, 'overlong UTF8');
  Reject(#$E0#$80#$80, 'three-byte overlong');
  Reject(#$ED#$A0#$80, 'surrogate UTF8');
  Reject(#$F4#$90#$80#$80, 'out-of-range UTF8');
  Reject(#$D0, 'truncated UTF8');
  Reject(#$D0'а', 'wrong continuation UTF8');
  Nested := '';
  for I := 1 to 258 do Nested := Nested + '(';
  for I := 1 to 258 do Nested := Nested + ')';
  Reject(Nested, 'bounded source depth');

  { Verify mechanics against the actual pinned Core4 file: parse only,
    never evaluate or claim a supported Core4 runtime. }
  F := TFileStream.Create('external/sens/lib/core4.lisp', fmOpenRead);
  try
    Check(F.Size > 0, 'pinned Core4 absent');
    Check(F.Size <= 16*1024*1024, 'pinned Core4 too large for G1.1');
    SetLength(S, F.Size);
    F.ReadBuffer(S[1], Length(S));
  finally F.Free; end;
  D := ReadUkrainianSource(S);
  try
    Check(Length(D.Forms) > 10, 'pinned Core4 top-level forms');
    Check(D.Forms[0].Kind = skList, 'pinned Core4 structural root');
    Check(D.Forms[0].Children[0].Text = 'визначити', 'pinned Core4 first form');
  finally D.Free; end;

  CheckNodeBoundary;

  WriteLn('SOURCE-READER-OK utf8=strict structure=ast source-bytes=preserved');
  WriteLn('SOURCE-READER-SCOPE lisp-projection-only core4=parse-only sens-binary=not-implemented');
end.
