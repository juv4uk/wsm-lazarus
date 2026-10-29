{ G2.30 — незалежний CLI-аудит D7-v2 на pinned шести проєкціях.
  Друковане слово НЕ стає викличним та не є числом D12+. }
program sensaudytd7;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.proektsii, wsm.d7audit;

const
  Labels:array[0..5] of RawByteString=
    ('ук','укр','san','en','LISP','sym');
var
  Catalog:TProektsiiCatalog;
  Audit:TD7AuditReport;
  C:SizeInt;
begin
  try
    if ParamCount<>1 then
      raise ED7AuditError.Create(
        'використання: sensaudytd7 <каталог pinned external/sens>');
    LoadPinnedProjections(ParamStr(1),Catalog);
    AuditPinnedD7(Catalog,Audit);
    { Жодного рядка stdout до завершення всього pinned admission. }
    WriteLn('Д7-КАНОН-ГАРАЗД координат=',Audit.Coordinates,
      ' друкованих=',Audit.Printable,' керувальних=',Audit.Controls);
    for C:=0 to 5 do
      WriteLn(Labels[C],': знаків=',Audit.Present[C],
        ' міждоменних-омонімів=',Audit.CrossDomainNames[C]);
    WriteLn('D7 LISP: 128 порожніх проєкцій; викличність не визначено');
  except
    on E:Exception do begin
      WriteLn(ErrOutput,RawByteString('АУДИТ-Д7-ПОМИЛКА: '),
        RawByteString(E.Message));
      Halt(2);
    end;
  end;
end.
