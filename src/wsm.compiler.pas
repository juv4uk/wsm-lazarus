unit wsm.compiler;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;
type ECompileError = class(Exception);
procedure CompileSource(const Source: RawByteString; Output: TStream);
procedure VerifySIR1(Input: TStream);
implementation

{ Structural validation only. SIR1 is NOT canonical .sens or executable IR. }
procedure VerifySIR1(Input: TStream);
var
  Magic: array[0..3] of Byte;
  Op, B, FirstChar, LastChar: Byte;
  Len: LongWord;
  I, Depth: Integer;
begin
  if Input.Size - Input.Position < 4 then
    raise ECompileError.Create('SIR1 header truncated');
  if Input.Read(Magic, 4) <> 4 then
    raise ECompileError.Create('SIR1 header read failed');
  if (Magic[0] <> Ord('S')) or (Magic[1] <> Ord('I')) or
     (Magic[2] <> Ord('R')) or (Magic[3] <> Ord('1')) then
    raise ECompileError.Create('invalid SIR1 magic');
  Depth := 0;
  while Input.Position < Input.Size do begin
    if Input.Read(Op, 1) <> 1 then
      raise ECompileError.Create('SIR1 opcode truncated');
    if Input.Size - Input.Position < 4 then
      raise ECompileError.Create('SIR1 token length truncated');
    Len := 0;
    for I := 0 to 3 do begin
      if Input.Read(B, 1) <> 1 then
        raise ECompileError.Create('SIR1 token length read failed');
      Len := Len or (LongWord(B) shl (8*I));
    end;
    case Op of
      0: begin
        if Len <> 0 then
          raise ECompileError.Create('SIR1 end marker has payload');
        if Depth <> 0 then
          raise ECompileError.Create('SIR1 unclosed list at end');
        if Input.Position <> Input.Size then
          raise ECompileError.Create('trailing bytes after SIR1 end marker');
        Exit;
      end;
      1, 2: begin
        if Len <> 0 then
          raise ECompileError.Create('SIR1 structural token has payload');
        if Op = 1 then begin
          if Depth = High(Depth) then
            raise ECompileError.Create('SIR1 nesting overflow');
          Inc(Depth);
        end else begin
          if Depth = 0 then
            raise ECompileError.Create('unexpected SIR1 close marker');
          Dec(Depth);
        end;
      end;
      3, 4: begin
        if Len = 0 then
          raise ECompileError.Create('SIR1 empty lexeme');
        if Int64(Len) > Input.Size - Input.Position then
          raise ECompileError.Create('SIR1 token payload truncated');
        if Op = 4 then begin
          if Len < 2 then
            raise ECompileError.Create('SIR1 string lexeme truncated');
          if Input.Read(FirstChar, 1) <> 1 then
            raise ECompileError.Create('SIR1 string beginning missing');
          Input.Seek(Int64(Len)-2, soCurrent);
          if Input.Read(LastChar, 1) <> 1 then
            raise ECompileError.Create('SIR1 string ending missing');
          if (FirstChar <> Ord('"')) or (LastChar <> Ord('"')) then
            raise ECompileError.Create('SIR1 malformed string boundary');
        end else
          Input.Seek(Int64(Len), soCurrent);
      end;
    else
      raise ECompileError.Create('unknown SIR1 opcode');
    end;
  end;
  raise ECompileError.Create('SIR1 end marker missing');
end;
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
