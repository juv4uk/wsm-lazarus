{ Український консольний доступ до оригінальних форм pinned Core4.
  НОМЕР — лише host-позиція у файлі, не числовий літерал SENS. }
program senscore4slice;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4slice;
var
  PackageData: TCore4SourcePackage;
  Number: Int64;
  Output: RawByteString;
begin
  if (ParamCount<>3) or (ParamStr(1)<>'--форма') then begin
    WriteLn(StdErr,'CORE4-ФОРМА-ПОМИЛКА: --форма КОРІНЬ НОМЕР');
    ExitCode:=64;
  end else if (not TryStrToInt64(ParamStr(3),Number)) or
              (Number<1) or (Number>High(SizeInt)) then begin
    WriteLn(StdErr,'CORE4-ФОРМА-ПОМИЛКА: номер має бути додатним цілим');
    ExitCode:=64;
  end else begin
    try
      SlicePinnedCore4(ParamStr(2),PackageData);
      if Number>Length(PackageData.Forms) then
        raise ECore4SliceError.Create('номер форми поза межами pinned Core4');
      Output:=PackageData.Forms[SizeInt(Number)-1].Source;
      Write(Output);
      ExitCode:=0;
    except on E:Exception do begin
      WriteLn(StdErr,'CORE4-ФОРМА-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end end;
  end;
end.
