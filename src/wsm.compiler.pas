unit wsm.compiler;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;
type ECompileError = class(Exception);
procedure CompileSource(const Source: RawByteString; Output: TStream);
implementation
procedure PutByte(O:TStream; B:Byte);
begin O.WriteBuffer(B,1); end;
procedure PutU32(O:TStream; N:LongWord);
var I:Integer;
begin for I:=0 to 3 do PutByte(O,Byte((N shr (I*8)) and 255)); end;
procedure PutToken(O:TStream; Op:Byte; const S:RawByteString);
begin
  PutByte(O,Op); PutU32(O,Length(S));
  if Length(S)>0 then O.WriteBuffer(S[1],Length(S));
end;
procedure CompileSource(const Source:RawByteString; Output:TStream);
var I,Start,Depth:SizeInt; C:AnsiChar; Token:RawByteString; Closed:Boolean;
begin
  { SIR1 is a private structural IR, not executable code or canonical .sens. }
  Token:='SIR1'; Output.WriteBuffer(Token[1],4);
  Depth:=0; I:=1;
  while I<=Length(Source) do begin
    C:=Source[I];
    if C in [' ',#9,#10,#13] then begin Inc(I); Continue; end;
    if C=';' then begin
      while (I<=Length(Source)) and (Source[I]<>#10) do Inc(I);
      Continue;
    end;
    if C='(' then begin PutToken(Output,1,''); Inc(Depth); Inc(I); Continue; end;
    if C=')' then begin
      if Depth=0 then raise ECompileError.Create('unexpected close parenthesis');
      PutToken(Output,2,''); Dec(Depth); Inc(I); Continue;
    end;
    if C='"' then begin
      Start:=I; Inc(I); Closed:=False;
      while I<=Length(Source) do begin
        if Source[I]=#92 then begin Inc(I,2); Continue; end;
        if Source[I]='"' then begin Inc(I); Closed:=True; Break; end;
        Inc(I);
      end;
      if not Closed then raise ECompileError.Create('unterminated string');
      PutToken(Output,4,Copy(Source,Start,I-Start));
      Continue;
    end;
    Start:=I;
    while I<=Length(Source) do begin
      C:=Source[I];
      if C in [' ',#9,#10,#13,'(',')',';','"'] then Break;
      Inc(I);
    end;
    if I=Start then raise ECompileError.Create('unexpected lexical character');
    PutToken(Output,3,Copy(Source,Start,I-Start));
  end;
  if Depth<>0 then raise ECompileError.Create('unclosed list');
  PutToken(Output,0,'');
end;
end.
