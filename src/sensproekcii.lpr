{ Host-перегляд шести проєкцій: не SENS evaluator або REPL. }
program sensproekcii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.projections;
const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
var
  Key: TDomainKey;
  Values: TProjectionSet;
  I: Integer;
begin
  try
    if ParamCount <> 2 then
      raise EProjectionError.Create('використання: sensproekcii <корінь pinned SENS> <точні біти>');
    Key := ExactKey(RawByteString(ParamStr(2)));
    Values := LoadPinnedProjections(ParamStr(1), KeyBits(Key));
    WriteLn('координата: D', Key.Width, ':', KeyBits(Key));
    for I := 0 to 5 do WriteLn(Labels[I], ': ', Values[I]);
  except
    on E: Exception do begin
      WriteLn(ErrOutput, 'ПРОЄКЦІЇ-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.
