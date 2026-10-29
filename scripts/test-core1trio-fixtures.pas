{ G6.150 — фізичні тест-свідки для ТРЬОХ справжніх pinned
  бібліотечних Core1 DEFINE з тієї самої пари D12.
  Два вхідні packed T5M атоми та три очікувані packed stdout
  беруться від чинного незалежного від AOT TCore1Selektor.
  Не виводимо expected через власну арифметику Pascal.
  Тестовий генератор зберігає кожен byte-for-byte свідок;
  Файлові потоки власні та звільняються finally.
  Питання: навіщо окрема кодова база oracle у CI?
  Чому не порівнювати тільки десяткові числа?
  Як тестуємо перехід D12→D24?
  Чому некоректний W7 не є вхідним числом D12? }
program test_core1trio_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.lowerpinnedcore1add,
  wsm.lowerpinnedcore1mul;
type
  TPair=record LabelText:String;A,B:LongInt;end;
const
  Cases:array[0..3] of TPair=(
    (LabelText:'01';A:7;B:3),
    (LabelText:'02';A:125;B:17),
    (LabelText:'03';A:-11;B:3),
    (LabelText:'04';A:0;B:-5));
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('ТРИ-ЯДРО1-ПРОВАЛ: '+Why) end;
procedure WriteRaw(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  Need(Length(Data)>0,'порожній фізичний свідок');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Data[1],Length(Data));finally F.Free end;
end;
function Bits12(N:LongInt):RawByteString;
var U,I:LongInt;
begin
  Need((N>=-2048) and (N<=2047),'вхідне число не в D12');
  U:=N;if U<0 then Inc(U,4096);
  Result:='';
  for I:=11 downto 0 do
    if (U and (1 shl I))<>0 then Result:=Result+'1'
    else Result:=Result+'0';
end;
function Atom(N:LongInt):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits12(N);
  Result:=EncodeT5M(W);
end;
var Root,Dest,LabelText,LPath,RPath:String;
    Left,Right:RawByteString;W:TExactWords;F:TextFile;I:Integer;
begin
  Need(ParamCount=2,'потрібно: корінь та каталог тесту');
  Root:=ParamStr(1);Dest:=IncludeTrailingPathDelimiter(ParamStr(2));
  Need(DirectoryExists(Dest),'не існує каталогу результатів');
  AssignFile(F,Dest+'cases.tsv');Rewrite(F);
  try
    for I:=0 to High(Cases) do begin
      LabelText:=Cases[I].LabelText;
      Left:=Atom(Cases[I].A);Right:=Atom(Cases[I].B);
      LPath:=Dest+LabelText+'.left.sens';
      RPath:=Dest+LabelText+'.right.sens';
      WriteRaw(LPath,Left);WriteRaw(RPath,Right);
      WriteRaw(Dest+LabelText+'.add.expected.sens',
        PinnedCore1AddCall(Root,Left,Right));
      WriteRaw(Dest+LabelText+'.sub.expected.sens',
        PinnedCore1SubCall(Root,Left,Right));
      WriteRaw(Dest+LabelText+'.mul.expected.sens',
        PinnedCore1MulCall(Root,Left,Right));
      WriteLn(F,LabelText,#9,Cases[I].A,#9,Cases[I].B,#9,
        Cases[I].A+Cases[I].B,#9,
        Cases[I].A-Cases[I].B,#9,
        Cases[I].A*Cases[I].B);
    end;
  finally CloseFile(F) end;
  SetLength(W,1);W[0]:='0000000';
  WriteRaw(Dest+'wrong-width.sens',EncodeT5M(W));
  WriteRaw(Dest+'corrupt.sens',#255);
  WriteLn('ТРИ-ЯДРО1-ФІЗИЧНІ-СВІДКИ: пар=4 pinned-викликів=12 signed=так D24=так');
end.
