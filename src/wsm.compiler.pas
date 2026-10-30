unit wsm.compiler;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;
type ECompileError = class(Exception);
procedure CompileSource(const Source: RawByteString; Output: TStream);
procedure VerifySIR1(Input: TStream);
type
  { Structural counters only. No language laws and no canonical .sens data. }
  TSIR1Stats = record
    Tokens, ListOpens, ListCloses, Atoms, Strings: Int64;
    PayloadBytes, MaxDepth: Int64;
  end;
procedure InspectSIR1(Input: TStream; out Stats: TSIR1Stats);
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
{ G6.2: bounded diagnostics on the private, already-verified SIR1 stream.
  No lexeme payload is allocated or interpreted; the upstream SENS reader
  remains the only semantic source. The input stream is rewound exactly to
  its original position before counting. }
{ G6.203 — запозичений SIR1 stream може змінитися між двома проходами.
  Лише локальний Pending отримує лічильники; зовнішній out Stats
  лишається нульовим за будь-якого збою. Публікація лише на End.
  Це host-структура, не SENS opcode, не семантичний D1 і не .sens.
  1) Чому перевірка першого проходу не гарантує стабільність другого?
  2) Чому out-результат має бути порожнім на винятку?
  3) Де знаходиться єдина точка публікації?
  4) Чому цей guard не є SENS oracle? }
procedure InspectSIR1(Input: TStream; out Stats: TSIR1Stats);
var
  StartPos: Int64;
  Pending: TSIR1Stats;
  Magic: array[0..3] of Byte;
  Op, B, FirstChar, LastChar: Byte;
  Len: LongWord;
  I, Depth: Int64;

  procedure Changed;
  begin
    raise ECompileError.Create('SIR1 changed after structural verification');
  end;

begin
  FillChar(Stats, SizeOf(Stats), 0);
  FillChar(Pending, SizeOf(Pending), 0);
  StartPos := Input.Position;
  VerifySIR1(Input);  { Перший прохід над запозиченим потоком. }

  { Другий прохід НЕ успадковує безпеку першого: TStream може змінитися.
    Повторно перевіряємо framing, межі й кінцевий маркер. Лише статистика,
    без нових законів, синтаксису або фізичного SENS декодування.
    1) Чому ранній End не означає перевірений EOF?
    2) Чому структурний Len має дорівнювати нулю?
    3) Чому out Stats публікуємо тільки після кінцевого EOF?
    4) Чому змінений borrowed stream не є новою мовною формою? }
  Input.Position := StartPos;
  if Input.Size - Input.Position < 4 then Changed;
  Input.ReadBuffer(Magic, 4);
  if (Magic[0] <> Ord('S')) or (Magic[1] <> Ord('I')) or
     (Magic[2] <> Ord('R')) or (Magic[3] <> Ord('1')) then Changed;
  Depth := 0;
  while Input.Position < Input.Size do begin
    if Input.Size - Input.Position < 5 then Changed;
    Input.ReadBuffer(Op, 1);
    Len := 0;
    for I := 0 to 3 do begin
      Input.ReadBuffer(B, 1);
      Len := Len or (LongWord(B) shl (8*I));
    end;
    Inc(Pending.Tokens);
    case Op of
      0: begin
        if (Len <> 0) or (Depth <> 0) or
           (Input.Position <> Input.Size) then Changed;
        Stats := Pending; { Єдина точка атомарної публікації. }
        Exit;
      end;
      1: begin
        if (Len <> 0) or (Depth = High(Int64)) then Changed;
        Inc(Pending.ListOpens);
        Inc(Depth);
        if Depth > Pending.MaxDepth then Pending.MaxDepth := Depth;
      end;
      2: begin
        if (Len <> 0) or (Depth = 0) then Changed;
        Inc(Pending.ListCloses);
        Dec(Depth);
      end;
      3, 4: begin
        if (Len = 0) or
           (Int64(Len) > Input.Size - Input.Position) then Changed;
        if Op = 4 then begin
          if Len < 2 then Changed;
          Input.ReadBuffer(FirstChar, 1);
          Input.Seek(Int64(Len)-2, soCurrent);
          Input.ReadBuffer(LastChar, 1);
          if (FirstChar <> Ord('"')) or (LastChar <> Ord('"')) then Changed;
          Inc(Pending.Strings);
        end else begin
          Input.Seek(Int64(Len), soCurrent);
          Inc(Pending.Atoms);
        end;
        Inc(Pending.PayloadBytes, Int64(Len));
      end;
    else
      Changed;
    end;
  end;
  Changed; { Відсутній кінцевий End після другого проходу. }
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
