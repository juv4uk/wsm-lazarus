program test_sourcelex;
{$mode objfpc}{$H+}{$codepage UTF8}
uses SysUtils, Classes, wsm.domain, wsm.sourcelex;

procedure Require(Ok: Boolean; const What: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'SOURCELEX-FAIL ', What);
    Halt(1);
  end;
end;

procedure MustReject(const S: RawByteString; const ErrorFragment: String);
var T: TSourceTokens; Failed: Boolean;
begin
  Failed := False;
  try
    ScanUkrainianSurface(S, T);
  except
    on E: ESourceLexError do begin
      Failed := True;
      Require(Pos('source:', E.Message) = 1, 'missing positional error');
      Require(Pos(ErrorFragment, E.Message) > 0,
        'unexpected error: ' + E.Message);
    end;
  end;
  Require(Failed, 'invalid input accepted');
end;

function ReadFileBytes(const FileName: String): RawByteString;
var F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead);
  try
    Require(F.Size <= 4*1024*1024, 'unexpectedly large pinned input');
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally F.Free; end;
end;

procedure TestPinnedFile(const FileName: String);
var S, Recovered: RawByteString; T: TSourceTokens; I, Opens: SizeInt;
begin
  S := ReadFileBytes(FileName);
  ScanUkrainianSurface(S, T);
  Recovered := RestoreUkrainianSurface(T);
  Require(Recovered = S, 'pinned file token round-trip differs');
  Opens := 0;
  for I := 0 to High(T) do begin
    if T[I].Kind = skOpen then Inc(Opens);
    if T[I].HasD2 then
      Require(T[I].D2.Width = 2, 'unexpected structural domain width');
  end;
  Require(Opens > 0, 'pinned file contains no list forms');
end;

var
  T: TSourceTokens;
  S, Tmp: RawByteString;
  I, NOpen, NClose, NDot, NString, NWord: SizeInt;
begin
  S := ' (ні . так) ; коментар з ) всередині' + #10 +
       '("рядок \" цитата" .5)' + #13#10;
  ScanUkrainianSurface(S, T);
  Require(RestoreUkrainianSurface(T) = S, 'lossless UTF-8 round-trip');
  Require(Length(T) > 10, 'trivia/comments lost');
  Require(T[1].Kind = skOpen, 'opening token missing');
  Require((T[1].StartByte = 2) and (T[1].Line = 1) and
    (T[1].Column = 2), 'wrong opening byte position');
  Require(T[1].HasD2 and SameKey(T[1].D2, ExactKey('10')),
    'opening exact D2 coordinate');
  NOpen := 0; NClose := 0; NDot := 0; NString := 0; NWord := 0;
  for I := 0 to High(T) do begin
    case T[I].Kind of
      skOpen: Inc(NOpen);
      skClose: Inc(NClose);
      skDot: begin
        Inc(NDot);
        Require(T[I].HasD2 and SameKey(T[I].D2, ExactKey('11')),
          'dot exact D2 coordinate');
      end;
      skString: Inc(NString);
      skWord: begin
        Inc(NWord);
        Require(not T[I].HasD2, 'word was given semantic coordinate');
      end;
    end;
    if T[I].Kind = skClose then
      Require(T[I].HasD2 and SameKey(T[I].D2, ExactKey('01')),
        'closing exact D2 coordinate');
  end;
  Require((NOpen=2) and (NClose=2) and (NDot=1) and
    (NString=1) and (NWord=3), 'token category counts invalid');
  Require(T[High(T)].Kind = skTrivia, 'terminal newline lost');
  Require((T[High(T)].Line = 2) and (T[High(T)].Column > 1),
    'byte position for CRLF invalid');
  ScanUkrainianSurface('', T);
  Require(Length(T)=0, 'empty input has tokens');
  Require(RestoreUkrainianSurface(T)='', 'empty reconstruction');

  { Keep UTF-8 strings, comments and surfaces distinct from D2 markers. }
  S := '(тест; коментар' + #10 + '"(не дужки)" так)';
  ScanUkrainianSurface(S, T);
  Require(RestoreUkrainianSurface(T)=S,
    'comment or string parentheses changed structural framing');

  { Positive real pinned input: structural scan only, no Core4 execution. }
  TestPinnedFile('external/sens/lib/domains/d3.lisp');
  TestPinnedFile('external/sens/lib/core4.lisp');

  { Negative morphology / exact byte positions, no historical SID8 reader. }
  MustReject(')', 'unmatched closing');
  MustReject('(', 'unclosed list');
  MustReject('(ні))', 'unmatched closing');
  MustReject('.', 'dot outside list');
  MustReject('"незакрито', 'unterminated string');
  MustReject('("рядок' + #92, 'unterminated string escape');
  MustReject('(' + #0 + ')', 'control byte');
  MustReject('(' + #1 + ')', 'control byte');
  MustReject('(' + #$C0 + #$AF + ')', 'UTF-8 leading');
  MustReject('(' + #$E0 + #$80 + #$80 + ')', 'noncanonical UTF-8');
  MustReject('(' + #$ED + #$A0 + #$80 + ')', 'noncanonical UTF-8');
  MustReject('(' + #$F4 + #$90 + #$80 + #$80 + ')', 'noncanonical UTF-8');
  MustReject('(' + #$D0, 'truncated UTF-8');
  MustReject('(' + #$D0 + #$20 + ')', 'UTF-8 continuation');
  Tmp := StringOfChar('(', 769) + StringOfChar(')',769);
  MustReject(Tmp, 'nesting exceeds reader bound');

  { A caller may not mutate token spans and still assert byte round-trip. }
  ScanUkrainianSurface('(ні)', T);
  T[1].StartByte := T[1].StartByte + 1;
  NDot := 0;
  try
    Tmp := RestoreUkrainianSurface(T);
  except
    on E: ESourceLexError do NDot := 1;
  end;
  Require(NDot=1, 'modified spans accepted as lossless');
  WriteLn('SOURCELEX-OK FPC UTF8+D2+positions+negative+pinned-core4 lexical-only; binary-sens=NOT_IMPLEMENTED; eval=NOT_VERIFIED');
end.
