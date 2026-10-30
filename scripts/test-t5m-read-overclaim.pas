{ G1.56: регресійний свідок для host-потоку, який бреше про
  кількість прийнятих байтів. Це фізична механіка, не закон SENS. }
program test_t5m_read_overclaim;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.t5madmission;

type
  TZavyshchenyiPotik = class(TMemoryStream)
  private
    FKilkist: Integer;
  public
    constructor Create(const Data: RawByteString);
    function Read(var Buffer; Count: Longint): Longint; override;
    property Kilkist: Integer read FKilkist;
  end;

constructor TZavyshchenyiPotik.Create(const Data: RawByteString);
begin
  inherited Create;
  FKilkist := 0;
  if Length(Data)>0 then WriteBuffer(Data[1], Length(Data));
  Position := 0;
end;

function TZavyshchenyiPotik.Read(var Buffer; Count: Longint): Longint;
begin
  Inc(FKilkist);
  if FKilkist=2 then Exit(Count+1);
  if Count>1 then Count:=1;
  Result:=inherited Read(Buffer,Count);
end;

procedure Perevir(Umova: Boolean; const Pryczyna: String);
begin
  if not Umova then begin
    WriteLn(StdErr,'T5M-READ-OVERCLAIM-ПОМИЛКА: ',Pryczyna);
    Halt(1);
  end;
end;

var Slova, StariSlova:TExactWords;
    Fizychni: RawByteString;
    Potik: TZavyshchenyiPotik;
    Spravnyi:TMemoryStream;
    Dokument:TD2Document;
    Adresy:TPhysicalWordSpans;
    Rezhym: Integer;
    Vidmova, Tochnist: Boolean;
begin
  SetLength(Slova,3);
  Slova[0]:='10'; Slova[1]:='1'; Slova[2]:='01';
  Fizychni:=EncodeT5M(Slova);
  Perevir(Length(Fizychni)=2,'неочікувана довжина фізичної форми');

  for Rezhym:=0 to 1 do begin
    { Спеціально залишаємо старі адреси перед аварійним викликом. }
    DecodeT5MWithLocations(EncodeT5M(Slova),StariSlova,Adresy);
    Perevir(Length(Adresy)=3,'немає попереднього фізичного snapshot');
    Potik:=TZavyshchenyiPotik.Create(Fizychni);
    Dokument:=nil;
    Vidmova:=False;
    Tochnist:=False;
    try
      try
        if Rezhym=0 then
          Dokument:=ReadCheckedD2Stream(Potik)
        else
          Dokument:=ReadCheckedD2WideLocatedStream(Potik,Adresy);
      except
        on E:ET5MAdmissionError do begin
          Vidmova:=True;
          Tochnist:=(E.ByteOffset=1) and (E.TritOffset=5) and
            (E.WordIndex=3) and (Pos('некоректний обсяг',E.Message)>0);
        end;
      end;
      Perevir(Vidmova and Tochnist,'не відхилено переповнений Read із точною адресою');
      Perevir(Dokument=nil,'видано частковий D2 документ');
      if Rezhym=1 then
        Perevir(Length(Adresy)=0,'залишено попередні фізичні адреси');
      Perevir((Potik.Kilkist=2) and (Potik.Position=1),
        'відмова сталася не після першого справжнього байта');
    finally
      Dokument.Free;
      Potik.Free;
    end;
  end;

  { Справний потік після двох відмов повертає початкову фізичну форму. }
  Spravnyi:=TMemoryStream.Create;
  Dokument:=nil;
  try
    Spravnyi.WriteBuffer(Fizychni[1],Length(Fizychni));
    Spravnyi.Position:=0;
    Dokument:=ReadCheckedD2WideLocatedStream(Spravnyi,Adresy);
    Perevir((Length(Dokument.Roots)=1) and
      (Dokument.Roots[0].Kind=dkList) and
      (Length(Dokument.Roots[0].Children)=1) and
      (Dokument.Roots[0].Children[0].Bits='1') and
      (Length(Adresy)=3),'після помилки не відновилося точне D2 читання');
  finally
    Dokument.Free;
    Spravnyi.Free;
  end;
  WriteLn('VERIFIED-T5M-READ-OVERCLAIM-PASS FPC=checked negative=2 ',
    'byte=1 trit=5 word=3 out=atomarnyi recovery=1 energy=NOT-MEASURED');
end.

{ Типи/життя: TZavyshchenyiPotik і TMemoryStream належать тесту,
  Document — owned результат (Free у finally); Adresy — динамічний
  масив точних фізичних координат. Вхід — два canonical байти T5M.
  Питання: 1) Чому Read > Count порушує host-контракт?
  2) Чому byte=1, а word=3? 3) Кому належить TStream?
  4) Чому невдалий out не зберігає старих адрес?
  5) Чому цей тест нічого не доводить про семантику D12+? }
