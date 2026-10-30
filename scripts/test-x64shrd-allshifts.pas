{ G6.252 — незалежний вичерпний машинний свідок існуючого SHRD.
  Зіставляємо всі 31 фізичних зсуви та всі 64 комбінації двох r32.
  Точні машинні байти виводимо через вже злитий host-кодер; інший
  процес GNU as збирає власний асемблерний текст для побайтового cmp.
  Це НЕ SENS evaluator, D7 або D12+ закон; тут тільки ISA x86-64.
  Хто володіє TX64Code, рядком, TFileStream та каталогом результатів?
  Чому reset перед кожним випадком захищає 256-байтну host-квоту?
  Чому всі 1 984 випадки сильніші за 64 вибіркові, але не доводять
  довільної SENS-компіляції чи енергоефективності? }
program test_x64shrd_allshifts;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64shrd;
const
  Names:array[0..7] of String=(
    'eax','ecx','edx','ebx','esp','ebp','esi','edi');
  ExpectedCases=31*8*8;
  ExpectedBytes=ExpectedCases*4;
var
  Code:TX64Code;
  Lines:TStringList;
  Bytes,ResultPath:RawByteString;
  Shift,Destination,Source,Count:LongInt;
  FileOut:TFileStream;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('SHRD-MATRIX: '+Why);
end;

procedure SaveBytes(const Path:String;const Data:RawByteString);
var OutFile:TFileStream;
begin
  OutFile:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then OutFile.WriteBuffer(Data[1],Length(Data));
  finally
    OutFile.Free
  end;
end;

begin
  Need(ParamCount=1,'pотрібен каталог приватного машинного свідка');
  ResultPath:=RawByteString(IncludeTrailingPathDelimiter(ParamStr(1)));
  Need(DirectoryExists(String(ResultPath)),'каталог результатів відсутній');
  Count:=0;
  Bytes:='';
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Lines.Add('.global _start');
    Lines.Add('_start:');
    for Shift:=1 to 31 do
      for Destination:=0 to 7 do
        for Source:=0 to 7 do begin
          X64Reset(Code);
          Code.PatchedRIP:='R';
          X64SHRD32(Code,TX64Reg(Destination),TX64Reg(Source),Shift);
          Need((Length(Code.Bytes)=4) and (Code.PatchedRIP='R'),
               'SHRD змінив RIP-мітку або розмір інструкції');
          Bytes:=Bytes+X64Image(Code);
          Lines.Add(' shrd '+Names[Destination]+','+
                    Names[Source]+','+IntToStr(Shift));
          Inc(Count);
        end;
    Need((Count=ExpectedCases) and (Length(Bytes)=ExpectedBytes),
         'неповна фізична матриця host SHRD');
    Need(Lines.Count=4+Count,'загублено машинний рядок GNU as');
    Lines.SaveToFile(String(ResultPath)+'shrd-full-matrix.s');
    SaveBytes(String(ResultPath)+'shrd-full-matrix.fpc.bin',Bytes);
  finally
    Lines.Free
  end;
  WriteLn('G6.252-SHRD-ALLSHIFTS-PASS matrix=',Count,
          ' bytes=',Length(Bytes),' shifts=31 registers=64');
end.
