{ G2.30. Механічний аудит pinned D7-v2 через вже допущений каталог.
  Це host-перевірка текстових даних, НЕ таблиця законів або викличність SENS. }
unit wsm.d7audit;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.proektsii;

type
  ED7AuditError = class(Exception);
  TD7AuditReport = record
    Coordinates, Printable, Controls: SizeInt;
    Present: array[0..5] of SizeInt;
    CrossDomainNames: array[0..5] of SizeInt;
  end;

procedure AuditPinnedD7(const Catalog:TProektsiiCatalog;
  out Report:TD7AuditReport);

implementation

procedure Require(OK:Boolean;const MessageText:String);
begin
  if not OK then raise ED7AuditError.Create(MessageText);
end;

{ Catalog — позичені FPC-managed масиви, що походять ВИКЛЮЧНО з
  LoadPinnedProjections. Candidate — локальний value record без власного
  heap; Report оприлюднюється атомарно після всіх перевірок.
  Текстова рівність порівнює повні RawByteString байти, без fold/NFC.
  D7 не є викличним доменом, D12+ не входить до цього каталогу. }
procedure AuditPinnedD7(const Catalog:TProektsiiCatalog;
  out Report:TD7AuditReport);
var
  Candidate:TD7AuditReport;
  D,I,J,C,K:SizeInt;
  V:RawByteString;
  IsPrintable:Boolean;
begin
  FillChar(Report,SizeOf(Report),0);
  FillChar(Candidate,SizeOf(Candidate),0);

  { Відхиляємо навіть структурно валідний, але підмінений ключ. }
  for D:=1 to 10 do begin
    Require(Length(Catalog[D])=(SizeInt(1) shl D),
      'Неповна pinned таблиця D'+IntToStr(D));
    for I:=0 to High(Catalog[D]) do
      Require((Catalog[D][I].Key.Width=D) and
        (Catalog[D][I].Key.Bits=I),
        'Підмінено точну координату D'+IntToStr(D));
  end;

  Candidate.Coordinates:=Length(Catalog[7]);
  for I:=0 to High(Catalog[7]) do begin
    IsPrintable:=(I>=32) and (I<=126);
    if IsPrintable then Inc(Candidate.Printable)
    else Inc(Candidate.Controls);

    { У D7 LISP завжди (), навіть для друкованих символів. }
    Require(Catalog[7][I].Surface[4]='',
      'D7 LISP не є проєкцією функції: '+IntToStr(I));

    for C:=0 to 5 do begin
      V:=Catalog[7][I].Surface[C];
      if IsPrintable and (C<>4) then begin
        Require(V<>'','Відсутня друкована проєкція D7: '+IntToStr(I));
        Inc(Candidate.Present[C]);
        { У межах конкретної проєкції Д7 жодні два W7
          не можуть мати те саме точне написання. }
        for J:=32 to I-1 do
          Require(Catalog[7][J].Surface[C]<>V,
            'Два D7 слова мають однакову текстову проєкцію');
      end else
        Require(V='','Керувальна або LISP адреса отримала текст');
    end;
  end;

  Require((Candidate.Coordinates=128) and
    (Candidate.Printable=95) and (Candidate.Controls=33),
    'Невірний профіль фізичного D7-v2');

  { Збіги з ІНШИМИ доменами — легальні текстові омоніми.
    Рахуємо їх для доказової діагностики, не для admission.
    Інший D та W ніколи не стають тотожними через написання. }
  for I:=32 to 126 do
    for C:=0 to 5 do
      if C<>4 then begin
        V:=Catalog[7][I].Surface[C];
        for D:=1 to 10 do
          if D<>7 then
            for K:=0 to High(Catalog[D]) do
              if Catalog[D][K].Surface[C]=V then
                Inc(Candidate.CrossDomainNames[C]);
      end;
  Report:=Candidate;
end;

{ Запитання до механізму:
  1) Чому ключ D7:0000000 не можна вгадати з нульового байта?
  2) Чому LISP=() у D7 не має значення D3:000?
  3) Чому омонім D7 і D10 не є колізією машинних координат?
  4) Чому байтове порівняння не виконує Unicode-normalization?
  5) Чому Report має залишитися нульовим після пізньої відмови? }
end.
