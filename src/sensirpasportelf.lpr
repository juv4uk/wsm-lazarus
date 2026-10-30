{ G6: доказовий паспорт ФАКТИЧНОЇ компіляції canonical T5M→WideIR→ELF64.
  Не додає законів SENS, не перекодовує .lisp і не виконує D7 dispatch.
  У stdout результат потрапляє лише ПІСЛЯ успішної компіляції. }
program sensirpasportelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.bind, wsm.wideir, wsm.wideirguard,
     wsm.irwidefront, wsm.elfgeometry;

const MaxPhysicalBytes=65536;
type EIRPassportError=class(Exception);

{ Параметр host-командного рядка звіряємо як UTF-8, а не за
  неявною Unicode/codepage конверсією FPC. Це НЕ SENS dispatch. }
function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Source обгортає позичений stdin FD; Buffer і його байти належать виклику.
  Читаємо фізичні БАЙТИ, не людську проєкцію; верхня межа до допуску.
  1) Чому не можна довіряти одному Read з каналу?
  2) Хто звільняє обидві обгортки потоку при відмові?
  3) Чому EOF host не створює новий SENS закон?
  4) Що відбувається з 65537-м фізичним байтом? }
function ReadPhysical:RawByteString;
var Source:THandleStream;Buffer:TMemoryStream;
    Chunk:array[0..1023] of Byte;N:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        N:=Source.Read(Chunk,SizeOf(Chunk));
        if N<0 then raise EIRPassportError.Create('помилка читання stdin');
        if N=0 then Break;
        if Buffer.Size>Int64(MaxPhysicalBytes)-N then
          raise EIRPassportError.Create('фізичний T5M перевищив 65536 байтів');
        Buffer.WriteBuffer(Chunk,N);
      until False;
      if Buffer.Size=0 then
        raise EIRPassportError.Create('порожній фізичний потік');
      SetLength(Result,SizeInt(Buffer.Size));
      Buffer.Position:=0;
      Buffer.ReadBuffer(Result[1],Length(Result));
    finally Buffer.Free end;
  finally Source.Free end;
end;

{ Тільки чинні pinned SENS таблиці дають вузькі ключі. W12+ лишається
  opaque до окремого семантичного admission у чинному compiler backend.
  Physical, Image і Report — FPC-керовані буфери, їх lifetime локальний.
  IR містить керовані вузли exact-width; Stats/Geometry — stack-записи.
  Результат — host UTF-8 паспорт, НЕ фізична програма й НЕ SENS oracle.
  1) Чому паспорт будується тільки ПІСЛЯ перевіреного ELF64?
  2) Чому Width+Bits разом важливіші за назву української функції?
  3) Чому статистика WideIR не доводить виконання Core1?
  4) Хто перевіряє точний D5/D6 закон перед native emitter?
  5) Чому hosted CI не може видати пакетну енергію в джоулях? }
function CompilePassport:RawByteString;
var Physical,Image:RawByteString;
    Tables:TDomainSet;
    IR:TWideIR;
    Stats:TWideIRGuardStats;
    Geometry:TELFGeometry;
    Head:TWideIRNode;
begin
  Physical:=ReadPhysical;
  LoadPinnedDomains('external/sens',Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Image:=BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Image,Geometry);
  if (Stats.Roots<>1) or (Length(IR.Nodes)<3) or
     (Length(IR.Roots)<>1) or (IR.Roots[0]<>0) or
     (IR.Nodes[0].Kind<>wkList) or
     (Geometry.Kind<>3) or (Geometry.Entry<>120) or
     (Geometry.FileBytes<>Length(Image)) then
    raise EIRPassportError.Create('відмовлено в машинному паспорті');
  Head:=IR.Nodes[1];
  if (Head.Kind<>wkAtom) or (not Head.HasPinnedKey) or
     (Head.ParentIndex<>0) or (Head.ChildIndex<>0) or
     (Head.Width<>Head.NarrowKey.Width) or
     (not SameKey(Head.NarrowKey,ExactKey(Head.Bits))) then
    raise EIRPassportError.Create('втрачено exact-голову WideIR');
  Result:=Ukr('КОМПІЛЯТОР-ПАСПОРТ-1')+#10+
    Ukr('вхід-байтів=')+IntToStr(Length(Physical))+#10+
    Ukr('коренів=')+IntToStr(Stats.Roots)+#10+
    Ukr('вузлів=')+IntToStr(Stats.Nodes)+#10+
    Ukr('фізичних-листків=')+IntToStr(Stats.PhysicalLeaves)+#10+
    Ukr('непрозорих-листків=')+IntToStr(Stats.OpaqueLeaves)+#10+
    Ukr('голова-ширина=')+IntToStr(Head.Width)+#10+
    Ukr('голова-біти=')+Head.Bits+#10+
    Ukr('тип-elf=')+IntToStr(Geometry.Kind)+#10+
    Ukr('elf-байтів=')+IntToStr(Geometry.FileBytes)+#10+
    Ukr('машинних-байтів=')+IntToStr(Geometry.MachineBytes)+#10+
    Ukr('енергія=НЕ-ВИМІРЯНО')+#10;
end;

{ Report — керований UTF-8 буфер; Stream обгортає позичений stdout FD,
  об'єкт звільняється після запису. WriteBuffer перевіряє повноту,
  тому помилка пристрою (наприклад, /dev/full) не є успішним паспортом.
  1) Чому Write не доводить завершення фізичного виводу?
  2) Хто володіє Report, а хто системним дескриптором?
  3) Чому недоступний stdout не змінює вже перевірений WideIR?
  4) Чому звіт не можна друкувати до перевірки ELF64? }
procedure WritePassport(const Report:RawByteString);
var Sink:THandleStream;
begin
  if Length(Report)=0 then
    raise EIRPassportError.Create('порожній машинний паспорт');
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    Sink.WriteBuffer(Report[1],Length(Report));
  finally Sink.Free end;
end;

var Report:RawByteString;
begin
  ExitCode:=0;
  if (ParamCount<>1) or (RawByteString(ParamStr(1))<>Ukr('--паспорт-фізичної-компіляції')) then
  begin
    Writeln(ErrOutput,Ukr('КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА: режим --паспорт-фізичної-компіляції'));
    ExitCode:=64;
  end
  else
    try
      {$IFNDEF LINUX}
      raise EIRPassportError.Create('потрібен Linux');
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise EIRPassportError.Create('потрібен x86-64');
      {$ENDIF}
      Report:=CompilePassport;
      WritePassport(Report);
    except on E:Exception do begin
      Writeln(ErrOutput,Ukr('КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА: '),E.Message);
      ExitCode:=2;
    end end;
end.
