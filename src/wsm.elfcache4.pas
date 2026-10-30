{ G6 — суто host-механізм кешування готового native ELF64.
  НЕ evaluator, не реєстр мовних законів і не дозвіл виклику Dn.
  Зберігає лише вже перевірені caller-ом byte-exact packed T5M → ELF.
  Усі чотири слоти живуть рівно стільки, скільки один host-сеанс. }
unit wsm.elfcache4;
{$mode objfpc}{$H+}{$codepage utf8}
interface
type
  TCache4Entry = record
    Physical: RawByteString;
    Image: RawByteString;
    Touch: QWord;
  end;

  TVerifiedELFCache4 = class
  private
    FEntries: array[0..3] of TCache4Entry;
    FClock: QWord;
  public
    function TryHit(const Physical: RawByteString;
                    out Image: RawByteString): Boolean;
    procedure StoreVerified(const Physical, Image: RawByteString);
  end;

implementation
uses SysUtils;

{ Physical borrowed: повний T5M, без текстового hash/імені/числа.
  Image — FPC-managed рядок із кешу; зміна його caller-ом не дозволена.
  Повертаємо host Boolean, не предикат SENS D1.
  1) Чому byte-by-byte рівність виключає колізію?
  2) Чому є лише 4 слоти і немає мережевого shared cache?
  3) Хто володіє Image після виходу з host-сеансу?
  4) Чому повторний hit не додає нового закону мови? }
function TVerifiedELFCache4.TryHit(const Physical: RawByteString;
                                  out Image: RawByteString): Boolean;
var I: SizeInt;
begin
  Result:=False;
  Image:='';
  if Physical='' then Exit;
  for I:=Low(FEntries) to High(FEntries) do
    if (FEntries[I].Image<>'') and
       (FEntries[I].Physical=Physical) then begin
      Inc(FClock);
      FEntries[I].Touch:=FClock;
      Image:=FEntries[I].Image;
      Exit(True);
    end;
end;

{ Лише успішний BuildOne+VerifySENSELF64 має право викликати цей метод.
  Жодна помилка не вставляє partial ELF, не витісняє слот і не
  змінює порядок LRU. Обмеження 4 × (65536 + 1048576) байтів
  плюс накладні витрати FPC; ключ — повні фізичні байти.
  1) Чому не кешується помилка компіляції?
  2) Чому при повному кеші витісняється найдавніший Touch?
  3) Чи допустима зміна pinned authority під час host-сеансу?
  4) Чому byte-exact T5M ≠ однакове людське ім'я? 
  5) Хто звільняє managed Physical/Image після Free? }
procedure TVerifiedELFCache4.StoreVerified(
  const Physical, Image: RawByteString);
var I, Slot: SizeInt; Oldest: QWord;
begin
  if (Length(Physical)<1) or (Length(Physical)>65536) or
     (Length(Image)<121) or (Length(Image)>1048576) then
    raise Exception.Create('кеш-4: host межа ключа або готового ELF');
  Slot:=-1;
  for I:=Low(FEntries) to High(FEntries) do begin
    if (FEntries[I].Image<>'') and
       (FEntries[I].Physical=Physical) then
      raise Exception.Create('кеш-4: повторне занесення вже наявного ключа');
    if (Slot<0) and (FEntries[I].Image='') then Slot:=I;
  end;
  if Slot<0 then begin
    Slot:=Low(FEntries);
    Oldest:=FEntries[Slot].Touch;
    for I:=Low(FEntries)+1 to High(FEntries) do
      if FEntries[I].Touch<Oldest then begin
        Slot:=I;
        Oldest:=FEntries[I].Touch;
      end;
  end;
  Inc(FClock);
  FEntries[Slot].Physical:=Physical;
  FEntries[Slot].Image:=Image;
  FEntries[Slot].Touch:=FClock;
end;
end.
