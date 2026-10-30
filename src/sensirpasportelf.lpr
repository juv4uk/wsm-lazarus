{ G6: доказовий паспорт ФАКТИЧНОЇ компіляції canonical T5M→WideIR→ELF64.
  Не додає законів SENS, не перекодовує .lisp і не виконує D7 dispatch.
  У stdout результат потрапляє лише ПІСЛЯ успішної компіляції. }
program sensirpasportelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.bind, wsm.wideir, wsm.wideirguard,
     wsm.irwidefront, wsm.elfgeometry;

const MaxPhysicalBytes=65536;
type EIRPassportError=class(Exception);

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
  Result:='КОМПІЛЯТОР-ПАСПОРТ-1'+#10+
    'вхід-байтів='+IntToStr(Length(Physical))+#10+
    'коренів='+IntToStr(Stats.Roots)+#10+
    'вузлів='+IntToStr(Stats.Nodes)+#10+
    'фізичних-листків='+IntToStr(Stats.PhysicalLeaves)+#10+
    'непрозорих-листків='+IntToStr(Stats.OpaqueLeaves)+#10+
    'голова-ширина='+IntToStr(Head.Width)+#10+
    'голова-біти='+Head.Bits+#10+
    'тип-elf='+IntToStr(Geometry.Kind)+#10+
    'elf-байтів='+IntToStr(Geometry.FileBytes)+#10+
    'машинних-байтів='+IntToStr(Geometry.MachineBytes)+#10+
    'енергія=НЕ-ВИМІРЯНО'+#10;
end;

var Report:RawByteString;
begin
  ExitCode:=0;
  if (ParamCount<>1) or (ParamStr(1)<>'--паспорт-фізичної-компіляції') then
  begin
    Writeln(ErrOutput,'КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА: режим --паспорт-фізичної-компіляції');
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
      Write(Report);
    except on E:Exception do begin
      Writeln(ErrOutput,'КОМПІЛЯТОР-ПАСПОРТ-ВІДМОВА: ',E.Message);
      ExitCode:=2;
    end end;
end.
