{ G2.30: шість людських проєкцій, без перетворення написів на закони. }
program senskolizii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.domain,wsm.proektsii;
const
  Labels:array[0..5] of RawByteString=('ук','укр','san','en','LISP','sym');
  Mask=8191;
type
  TSeen=record
    Name:RawByteString;
    First:TDomainKey;
    Hits:SizeInt;
  end;
  TExample=record
    Found:Boolean;
    First,Second:TDomainKey;
  end;
var
  Catalog:TProektsiiCatalog;
  Seen:array of TSeen;
  Pairs:array[0..5] of Int64;
  Example:array[0..5] of TExample;
  Col,D,R,Slot,N:SizeInt;
  Spelling:RawByteString;
  K:TDomainKey;
{ Хеш — механічна адреса. Рівність — лише побайтове UTF-8 порівняння. }
function Bucket(const S:RawByteString):SizeInt;
var H,I:SizeInt;
begin
  H:=5381;
  for I:=1 to Length(S) do
    H:=((H shl 5) xor (H shr 8) xor Ord(S[I])) and Mask;
  Result:=H;
end;
begin
  try
    FillChar(Pairs,SizeOf(Pairs),0);
    FillChar(Example,SizeOf(Example),0);
    if ParamCount<>1 then raise EProektsiiError.Create(
      'використання: senskolizii <корінь pinned SENS>');
    LoadPinnedProjections(ParamStr(1),Catalog);
    N:=0;
    for D:=1 to 10 do Inc(N,Length(Catalog[D]));
    if (N<>2046) or (Length(Catalog[7])<>128) then
      raise EProektsiiError.Create('Неповний pinned D1–D10 / D7');
    for Col:=0 to 5 do begin
      SetLength(Seen,0);
      SetLength(Seen,Mask+1);
      for D:=1 to 10 do
        for R:=0 to High(Catalog[D]) do begin
          Spelling:=Catalog[D][R].Surface[Col];
          if Spelling='' then Continue; { () означає відсутність поверхні }
          K:=Catalog[D][R].Key;
          Slot:=Bucket(Spelling);
          while (Seen[Slot].Hits<>0) and
                (Seen[Slot].Name<>Spelling) do
            Slot:=(Slot+1) and Mask;
          if Seen[Slot].Hits=0 then begin
            Seen[Slot].Name:=Spelling;
            Seen[Slot].First:=K;
            Seen[Slot].Hits:=1;
          end else begin
            Inc(Pairs[Col],Seen[Slot].Hits);
            if not Example[Col].Found then begin
              Example[Col].Found:=True;
              Example[Col].First:=Seen[Slot].First;
              Example[Col].Second:=K;
            end;
            Inc(Seen[Slot].Hits);
          end;
        end;
    end;
    { Жодного stdout до повного pinned admission й підрахунку. }
    WriteLn(RawByteString('Перевірено pinned D1–D10: координат='),N,
      RawByteString('; D7=128; колонок=6'));
    for Col:=0 to 5 do begin
      Write(Labels[Col],RawByteString(': пар='),Pairs[Col]);
      if Example[Col].Found then
        Write(RawByteString('; приклад=D'),Example[Col].First.Width,':',
          KeyBits(Example[Col].First),' + D',
          Example[Col].Second.Width,':',
          KeyBits(Example[Col].Second));
      WriteLn;
    end;
  except
    on E:Exception do begin
      WriteLn(ErrOutput,RawByteString('АУДИТ-ПРОЄКЦІЙ-ПОМИЛКА: '),
        RawByteString(E.Message));
      Halt(2);
    end;
  end;
end.
