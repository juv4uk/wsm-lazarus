{ Командний механічний опис pinned Core4. Без семантики й виконання. }
program senscore4manifest;
{$mode objfpc}{$H+}
uses SysUtils, wsm.core4manifest;
var Data:RawByteString;
begin
  if (ParamCount<>2) or (ParamStr(1)<>'--опис') then begin
    WriteLn(StdErr,'CORE4-ОПИС-ПОМИЛКА: команда --опис корінь');
    ExitCode:=64;
  end else begin
    try
      Data:=Core4Manifest(ParamStr(2));
      Write(Data);
      ExitCode:=0;
    except on E:Exception do begin
      WriteLn(StdErr,'CORE4-ОПИС-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end end;
  end;
end.
