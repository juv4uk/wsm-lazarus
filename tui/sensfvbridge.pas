{ Тільки HOST-міст до вже наявного senscore1repl, не evaluator SENS.
  Вхід — UTF-8 байти людської проєкції, НЕ канонічні .sens. }
unit sensfvbridge;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, Classes, Process;
type
  ESensFVBridge = class(Exception);
  TSensFVBridge = class
  private
    FProcess: TProcess;
    FQueue: TStringList;
    FStdout, FStderr: RawByteString;
    FReady, FBusy, FFinished: Boolean;
    procedure Accept(const Source: Char; const Chunk: RawByteString);
    procedure Drain(const Source: Char);
  public
    constructor Create(const BinaryPath, RepositoryRoot: String);
    destructor Destroy; override;
    procedure Send(const Line: RawByteString);
    procedure Poll;
    function PopLine(out Line: RawByteString; out IsError: Boolean): Boolean;
    property Ready: Boolean read FReady;
    property Busy: Boolean read FBusy;
    property Finished: Boolean read FFinished;
  end;
function ValidInputUTF8(const Line: RawByteString): Boolean;
function SafeTerminalText(const Line: RawByteString): RawByteString;
implementation

{ Не створюємо SENS reader чи Unicode-normalization.
  Заборонено NUL/ESC/CR/LF, C1, overlong, surrogate та обрізану UTF-8. }
function ValidInputUTF8(const Line: RawByteString): Boolean;
var I, N, B, B1, J: SizeInt;
begin
  Result := False;
  if (Length(Line) = 0) or (Length(Line) > 240) then Exit;
  I := 1;
  while I <= Length(Line) do begin
    B := Ord(Line[I]);
    if B < $80 then begin
      if B < $20 then Exit;
      Inc(I);
      Continue;
    end;
    if (B >= $C2) and (B <= $DF) then N := 2
    else if (B >= $E0) and (B <= $EF) then N := 3
    else if (B >= $F0) and (B <= $F4) then N := 4
    else Exit;
    if I + N - 1 > Length(Line) then Exit;
    for J := 1 to N-1 do
      if (Ord(Line[I+J]) < $80) or (Ord(Line[I+J]) > $BF) then Exit;
    B1 := Ord(Line[I+1]);
    if ((B=$E0) and (B1<$A0)) or ((B=$ED) and (B1>=$A0)) or
       ((B=$F0) and (B1<$90)) or ((B=$F4) and (B1>$8F)) then Exit;
    if (B=$C2) and (B1>=$80) and (B1<=$9F) then Exit;
    Inc(I,N);
  end;
  Result := True;
end;

function SafeTerminalText(const Line: RawByteString): RawByteString;
var I: SizeInt; B: Byte;
begin
  Result := Line;
  for I := 1 to Length(Result) do begin
    B := Ord(Result[I]);
    if (B < $20) or (B = $7F) then Result[I] := '?';
  end;
end;

constructor TSensFVBridge.Create(const BinaryPath, RepositoryRoot: String);
begin
  inherited Create;
  FQueue := TStringList.Create;
  FProcess := TProcess.Create(nil);
  try
    if not FileExists(BinaryPath) then
      raise ESensFVBridge.Create('немає перевіреного Core1 REPL: '+BinaryPath);
    if not DirectoryExists(RepositoryRoot) then
      raise ESensFVBridge.Create('немає кореня pinned проєкту');
    FProcess.Executable := ExpandFileName(BinaryPath);
    FProcess.Parameters.Add(ExpandFileName(RepositoryRoot));
    FProcess.CurrentDirectory := ExpandFileName(RepositoryRoot);
    FProcess.Options := [poUsePipes];
    FProcess.Execute;
  except
    FreeAndNil(FProcess);
    FreeAndNil(FQueue);
    raise;
  end;
end;

destructor TSensFVBridge.Destroy;
begin
  if FProcess <> nil then begin
    if FProcess.Running then
      FProcess.Terminate(0);
    FreeAndNil(FProcess);
  end;
  FreeAndNil(FQueue);
  inherited Destroy;
end;

procedure TSensFVBridge.Send(const Line: RawByteString);
var Wire: RawByteString;
begin
  if not FReady then raise ESensFVBridge.Create('Core1 REPL ще не готовий');
  if FBusy then raise ESensFVBridge.Create('попередня форма ще виконується');
  if FFinished or (not FProcess.Running) then
    raise ESensFVBridge.Create('Core1 REPL завершився');
  if not ValidInputUTF8(Line) then
    raise ESensFVBridge.Create('вхід не є повним UTF-8 до 240 байтів');
  Wire := Line + #10;
  FProcess.Input.WriteBuffer(Wire[1], Length(Wire));
  FBusy := True;
end;

procedure TSensFVBridge.Accept(const Source: Char; const Chunk: RawByteString);
var I, FromPos: SizeInt; Line: RawByteString;
    Buffer: ^RawByteString;
begin
  if Source = 'O' then Buffer := @FStdout else Buffer := @FStderr;
  if Length(Buffer^) + Length(Chunk) > 8192 then begin
    Buffer^ := '';
    if FQueue.Count >= 256 then FQueue.Delete(0);
    FQueue.Add('Eперевищено host-ліміт рядка процесу');
    FBusy := False;
    FFinished := True;
    if FProcess.Running then FProcess.Terminate(1);
    Exit;
  end;
  Buffer^ := Buffer^ + Chunk;
  FromPos := 1;
  for I := 1 to Length(Buffer^) do
    if Buffer^[I] = #10 then begin
      Line := Copy(Buffer^, FromPos, I-FromPos);
      if (Length(Line)>0) and (Line[Length(Line)]=#13) then
        SetLength(Line, Length(Line)-1);
      if FQueue.Count >= 256 then FQueue.Delete(0);
      FQueue.Add(Source + String(SafeTerminalText(Line)));
      if Source = 'O' then begin
        if not FReady then begin
          { Єдиний host startup protocol чинного Core1: рядок Команди. }
          if Pos(':help, :quit.',String(Line))>0 then FReady := True;
        end else if FBusy then FBusy := False;
      end else begin
        { Протокол чинного Core1: stderr пише завершену діагностику LF.
          Проміжний prompt без LF не є відповіддю.
          Не порівнюємо текст помилки за Unicode локаллю. }
        FBusy := False;
      end;
      FromPos := I+1;
    end;
  Buffer^ := Copy(Buffer^, FromPos, MaxInt);
end;

procedure TSensFVBridge.Drain(const Source: Char);
var Count: LongInt; Chunk: RawByteString;
begin
  if Source='O' then Count := FProcess.Output.NumBytesAvailable
  else Count := FProcess.Stderr.NumBytesAvailable;
  if Count > 4096 then Count := 4096;
  if Count <= 0 then Exit;
  SetLength(Chunk,Count);
  if Source='O' then Count := FProcess.Output.Read(Chunk[1],Count)
  else Count := FProcess.Stderr.Read(Chunk[1],Count);
  if Count <= 0 then Exit;
  SetLength(Chunk,Count);
  Accept(Source,Chunk);
end;

procedure TSensFVBridge.Poll;
begin
  if FFinished then Exit;
  Drain('O');
  Drain('E');
  if not FProcess.Running then begin
    Drain('O'); Drain('E');
    FFinished:=True; FBusy:=False;
    if FQueue.Count >= 256 then FQueue.Delete(0);
    FQueue.Add('Eдочірній Core1 REPL завершився');
  end;
end;

function TSensFVBridge.PopLine(out Line: RawByteString;
  out IsError: Boolean): Boolean;
var Item: String;
begin
  Result := FQueue.Count > 0;
  if not Result then Exit;
  Item := FQueue[0];
  FQueue.Delete(0);
  IsError := (Length(Item)>0) and (Item[1]='E');
  Line := RawByteString(Copy(Item,2,MaxInt));
end;
end.
