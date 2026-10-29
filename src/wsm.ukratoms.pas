{ G2.50. Зв'язування ПОВНОЇ проєкції укр з pinned точними координатами.
  ВИКЛЮЧНО host-індекс даних: ні нових законів, ні викличності D7,
  ні неявного виконання .lisp чи перетворення його на .sens.
  Читач, хеш-індекс та обхід AST — вже існуючі механізми. }
unit wsm.ukratoms;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.proektsii, wsm.bindindex, wsm.bindatoms;
type
  EUkrAtomsError = class(Exception);
procedure BuildFullUkrIndex(const Catalog: TProektsiiCatalog;
  out Index: TBindIndex);
procedure CollectFullUkrAtoms(const Source: RawByteString;
  const Catalog: TProektsiiCatalog; out Atoms: TAtomRecords);
implementation
uses wsm.domain, wsm.bind, wsm.source;

procedure BuildFullUkrIndex(const Catalog: TProektsiiCatalog;
  out Index: TBindIndex);
var
  Tables: TDomainSet;
  D, I: SizeInt;
begin
  { Не залишати старого чи напівпобудованого індексу на пізній відмові. }
  SetLength(Index.Slots, 0);
  Index.Count := 0;
  for D := FirstDomain to LastDomain do begin
    if Length(Catalog[D]) <> (SizeInt(1) shl D) then
      raise EUkrAtomsError.CreateFmt('Неповна pinned таблиця укр D%d',[D]);
    SetLength(Tables[D],Length(Catalog[D]));
    for I := 0 to High(Catalog[D]) do begin
      if (Catalog[D][I].Key.Width <> D) or
         (Catalog[D][I].Key.Bits <> I) then
        raise EUkrAtomsError.CreateFmt(
          'Пошкоджена точна координата укр D%d, рядок %d',[D,I]);
      Tables[D][I].Key := Catalog[D][I].Key;
      { Дослівний pinned укр (колонка 1), без транслітерації/іменного dispatch. }
      Tables[D][I].Ukrainian := Catalog[D][I].Surface[1];
    end;
  end;
  try
    { Чинний механізм відхиляє дублікати між доменами; немає другого індексу. }
    BuildBindIndex(Tables,Index);
  except
    on E: EBindError do
      raise EUkrAtomsError.Create('Неоднозначна або хибна pinned укр: '+E.Message);
  end;
end;

procedure CollectFullUkrAtoms(const Source: RawByteString;
  const Catalog: TProektsiiCatalog; out Atoms: TAtomRecords);
var Index: TBindIndex; Doc: TSourceDocument; Candidate: TAtomRecords;
begin
  SetLength(Atoms,0);
  BuildFullUkrIndex(Catalog,Index);
  Doc := ReadUkrainianSource(Source);
  try
    { Існуючий AST census зберігає точні UTF-8 byte positions,
      невідомі лексичні імена та не сприймає skString як викличний атом. }
    CollectSourceAtoms(Doc,Index,Candidate);
  finally
    Doc.Free;
  end;
  { Єдина публікація після повного допуску. FPC керує lifetime масиву. }
  Atoms := Candidate;
end;
end.
