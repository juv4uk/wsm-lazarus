{ G6.163 — БЕЗПЕРЕРВНИЙ HOST-сеанс компілятора, не потік мови SENS.
  Кожен вхідний кадр: LE32 довжина + фізичний canonical T5M.
  Кожна відповідь: 1 host status byte + LE32 довжина + ELF або діагностика.
  status=1: перевірений native ELF64 PIE; status=0: UTF-8 помилка.
  Після помилкового, але повністю отриманого кадру продовжуємо роботу.
  Мовних законів, Core1/Core4 чи D7 диспетчера тут немає. }
program senswidesesiiaelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.irwidefront, wsm.elfgeometry, wsm.elfcache4;
const
  MaxFrames = 64;
  MaxPhysical = 65536;
  MaxELF = 1048576;
  MaxDiagnostic = 4096;
type
  EWideSessionError = class(Exception);
  { Два FPC-керовані байтові буфери; це HOST cache, не SENS значення. }
  TCacheEntry = record
    Physical: RawByteString; { exact canonical packed .sens }
    Image: RawByteString;    { повністю перевірений x86-64 PIE ELF }
  end;
  TTwoEntries = array[0..1] of TCacheEntry;

function Ukr(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

{ Borrowed host-stream, Result/Header — owned managed bytes. EOF дозволений
  лише між 4-байтовими host заголовками; short read не завершує кадр.
  1) Чому EOF посеред кадру не є завершенням D2?
  2) Хто відповідає за завершення всього host-сеансу?
  3) Чому тут не декодуються бітові координати самостійно?
  4) Що відбувається з managed Result під час винятку? }
function ReadExact(Src: TStream; Count: SizeInt; BoundaryEOF: Boolean;
                   out Data: RawByteString): Boolean;
var Got,N: SizeInt;
begin
  Data := '';
  Result := False;
  if Count <= 0 then
    raise EWideSessionError.Create(Ukr('неприпустима host-довжина читання'));
  SetLength(Data,Count);
  Got := 0;
  while Got < Count do begin
    N := Src.Read(Data[Got+1],Count-Got);
    if N < 0 then
      raise EWideSessionError.Create(Ukr('помилка читання stdin'));
    if N = 0 then begin
      if BoundaryEOF and (Got=0) then begin
        Data := '';
        Exit(False);
      end;
      raise EWideSessionError.Create(Ukr('обірвано host-заголовок або тіло'));
    end;
    Inc(Got,N);
  end;
  Result := True;
end;

{ LE32 — ЛИШЕ host протокол. QWord не допускає переповнення SizeInt.
  Значення не є ні числом SENS D12+, ні семантичним бітовим ключем. }
function DecodeHostLength(const Header: RawByteString): QWord;
begin
  if Length(Header)<>4 then
    raise EWideSessionError.Create(Ukr('немає 4 байтів заголовка'));
  Result := QWord(Byte(Header[1])) or
            (QWord(Byte(Header[2])) shl 8) or
            (QWord(Byte(Header[3])) shl 16) or
            (QWord(Byte(Header[4])) shl 24);
end;

{ Payload owned — байтова копія ELF або UTF-8 діагностики.
  Status=1/0 є HOST каналом, не SENS D1 значенням.
  Тут немає накопичення відповідей: одразу після повного admission одного
  кадру виводиться цілісна відповідь; write error може лишити префікс.
  1) Чому статус 0 не є D1:0?
  2) Чому перевірка ELF передує відкриттю stdout?
  3) Хто гарантує canonical T5M вихід виконаного ELF?
  4) Чи обіцяємо atomic pipe-write при відмові ОС? }
procedure Respond(Dst: TStream; Success: Boolean; const Payload: RawByteString);
var Header: array[0..4] of Byte; Len: QWord;
begin
  Len := QWord(Length(Payload));
  if (Len=0) or (Len>MaxELF) or
     ((not Success) and (Len>MaxDiagnostic)) then
    raise EWideSessionError.Create(Ukr('відповідь поза квотою host-сеансу'));
  if Success then Header[0] := 1 else Header[0] := 0;
  Header[1] := Byte(Len and $FF);
  Header[2] := Byte((Len shr 8) and $FF);
  Header[3] := Byte((Len shr 16) and $FF);
  Header[4] := Byte((Len shr 24) and $FF);
  Dst.WriteBuffer(Header,SizeOf(Header));
  Dst.WriteBuffer(Payload[1],Length(Payload));
end;

{ Borrowed Physical — тільки повне окреме .sens/T5M тіло;
  Image — owned FPC RawByteString. Жодної host-конверсії до D7/числа.
  BuildVerifiedWideELF повторно перевіряє pinned domain-width bits,
  викличність підтриманого профілю, D12+ admission і native backend.
  1) Чому Width=12 не перетворюється автоматично на число?
  2) Чому цей API не є загальним evaluator?
  3) Як перевірити відповідь незалежним SENS CLI?
  4) Хто звільняє Image після повернення? }
function BuildOne(const Physical: RawByteString): RawByteString;
var G: TELFGeometry;
begin
  Result := BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Result,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Result)) or
     (Length(Result)>MaxELF) then
    raise EWideSessionError.Create(Ukr('після компіляції відхилено ELF64 PIE'));
end;

{ Відмову в межах валідного host-кадру повертаємо status=0 і продовжуємо.
  Некоректне кадрування >65536 або обірване тіло — термінальна помилка.
  Кожен THandleStream володіє лише wrapper, НЕ стандартним дескриптором.
  1) Чому malformed T5M відновлюваний, а short frame ні?
  2) Чому не можна прийняти 65-й кадр?
  3) Чому LE32 кадри не становлять єдиний .sens документ?
  4) Яка різниця між response status і ExitCode процесу?
  5) Як гарантується відсутність старого ELF після помилки? }
{ Hits/Misses — host облік, не вимір енергії або закон мови. }
procedure ReportCache(Hits, Misses: SizeInt);
var Err: THandleStream; Line: RawByteString;
begin
  Line := Ukr('КЕШ-СЕАНС-ГОТОВО hits=') + IntToStr(Hits) +
          ' misses=' + IntToStr(Misses) + #10;
  Err := THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(Line[1],Length(Line));
  finally Err.Free end;
end;

{ Opt-in кеш одного останнього ELF. LastPhysical і LastImage — керовані
  FPC RawByteString з lifetime рівно одного host-процесу.
  <=65536+1048576 B для фізичного джерела й машинного образу.
  Ключ — ПОВНІ packed T5M байти, не хеш/проєкція D7/число/ім'я.
  HIT можливий лише після успішного BuildOne+VerifySENSELF64.
  Pinned external/sens не змінюємо під час поточного host-сеансу.
  1) Чому рівність повних байтів унеможливлює хеш-колізію?
  2) Чому не кешуємо виключення та часткові результати?
  3) Чому повторний HIT не є новим семантичним законом SENS?
  4) Чому один cached ELF займає обмежену пам'ять?
  5) Хто звільняє керовані рядки після виходу з Serve? }

{ Двомісний LRU обмежений 2 × (65536 + 1048576) байтів плюс FPC
  managed string overhead; другий режим opt-in і не змінює cache-1.
  Key = ВЕСЬ byte-exact packed T5M, не checksum, ім'я чи D7 surface.
  LRU фіксує останній успішно використаний slot, негатив не витісняє.
  Усі кешовані ELF проходять раніше BuildOne+VerifySENSELF64.
  1) Чому немає колізії ключа при однаковій довжині різних байтів?
  2) Чому виключення BuildOne не витісняє cache?
  3) Чому LRU — механізм host, а не закон SENS?
  4) Чому старі режими не отримують cache-2 state?
  5) Хто звільняє два FPC-managed RawByteString після Serve? }
procedure ReportTwoCache(Hits,Misses:SizeInt);
var Err:THandleStream;Line:RawByteString;
begin
  Line:=Ukr('КЕШ-2-СЕАНС-ГОТОВО hits=')+IntToStr(Hits)+
        ' misses='+IntToStr(Misses)+#10;
  Err:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(Line[1],Length(Line));
  finally Err.Free end;
end;

{ Чотири слоти — opt-in host-прискорення для 3–4 повторюваних форм.
  Старі режими 0/1/2 не змінюють ні cache-state, ні машинний вихід. }
procedure ReportFourCache(Hits,Misses:SizeInt);
var Err:THandleStream;Line:RawByteString;
begin
  Line:=Ukr('КЕШ-4-СЕАНС-ГОТОВО hits=')+IntToStr(Hits)+
        ' misses='+IntToStr(Misses)+#10;
  Err:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(Line[1],Length(Line));
  finally Err.Free end;
end;

procedure Serve(CacheMode:SizeInt);
var Src,Dst: THandleStream;
    Cache4: TVerifiedELFCache4;
    Header,Physical,Image,Diagnostic,LastPhysical,LastImage: RawByteString;
    Entries:TTwoEntries;
    LengthPhysical: QWord;
    Count,Hits,Misses,RecentSlot,HitSlot,Slot: SizeInt;
begin
  Count := 0;
  Hits := 0;
  Misses := 0;
  LastPhysical := '';
  LastImage := '';
  RecentSlot := -1;
  for Slot:=0 to 1 do begin
    Entries[Slot].Physical:='';
    Entries[Slot].Image:='';
  end;
  Cache4:=nil;
  if CacheMode=3 then Cache4:=TVerifiedELFCache4.Create;
  try
    Src := THandleStream.Create(TextRec(Input).Handle);
    try
    Dst := THandleStream.Create(TextRec(Output).Handle);
    try
      while ReadExact(Src,4,True,Header) do begin
        Inc(Count);
        if Count>MaxFrames then
          raise EWideSessionError.Create(Ukr('більше 64 host-кадрів'));
        LengthPhysical := DecodeHostLength(Header);
        if LengthPhysical>MaxPhysical then
          raise EWideSessionError.Create(Ukr('host-кадр перевищив 65536 байтів'));
        if LengthPhysical=0 then begin
          Respond(Dst,False,Ukr('порожня фізична програма'));
          Continue;
        end;
        if not ReadExact(Src,SizeInt(LengthPhysical),False,Physical) then
          raise EWideSessionError.Create(Ukr('відсутнє фізичне тіло'));
        Image := '';
        try
          if CacheMode=3 then begin
            { Кеш шукає ПОВНИЙ T5M ключ, а не семантичне ім'я чи хеш.
              StoreVerified виконуємо тільки ПІСЛЯ повного BuildOne,
              отже відхилена програма не змінює LRU. }
            if Cache4.TryHit(Physical,Image) then Inc(Hits)
            else begin
              Image:=BuildOne(Physical);
              Cache4.StoreVerified(Physical,Image);
              Inc(Misses);
            end;
          end else if CacheMode=2 then begin
            HitSlot:=-1;
            for Slot:=0 to 1 do
              if (Entries[Slot].Image<>'') and
                 (Entries[Slot].Physical=Physical) then begin
                HitSlot:=Slot;
                Break;
              end;
            if HitSlot>=0 then begin
              Image:=Entries[HitSlot].Image;
              RecentSlot:=HitSlot;
              Inc(Hits);
            end else begin
              { Спершу повний pinned T5M/D2/WideIR/ELF admission.
                Якщо BuildOne кидає, Entries/RecentSlot лишаються
                незмінні: відмова не отруює жодного кешованого ELF. }
              Image:=BuildOne(Physical);
              if Entries[0].Image='' then Slot:=0
              else if Entries[1].Image='' then Slot:=1
              else Slot:=1-RecentSlot;
              Entries[Slot].Physical:=Physical;
              Entries[Slot].Image:=Image;
              RecentSlot:=Slot;
              Inc(Misses);
            end;
          end else if (CacheMode=1) and (LastImage<>'') and
                      (LastPhysical=Physical) then begin
            Image := LastImage;
            Inc(Hits);
          end else begin
            Image := BuildOne(Physical);
            if CacheMode=1 then begin
              LastPhysical := Physical;
              LastImage := Image;
              Inc(Misses);
            end;
          end;
          Respond(Dst,True,Image);
        except
          on E:Exception do begin
            Diagnostic := RawByteString(E.Message);
            if Length(Diagnostic)>MaxDiagnostic then
              Diagnostic:=Ukr('діагностика перевищила host-квоту');
            if Length(Diagnostic)=0 then
              Diagnostic:=Ukr('відхилено фізичний T5M кадр');
            Respond(Dst,False,Diagnostic);
          end;
        end;
      end;
      if Count=0 then
        raise EWideSessionError.Create(Ukr('порожній host-сеанс'));
      if CacheMode=1 then ReportCache(Hits,Misses)
      else if CacheMode=2 then ReportTwoCache(Hits,Misses)
      else if CacheMode=3 then ReportFourCache(Hits,Misses);
    finally Dst.Free end;
    finally Src.Free end;
  finally Cache4.Free end;
end;

procedure Fail(const Why: RawByteString);
var Err: THandleStream; Line: RawByteString;
begin
  Line := Ukr('ШИРОКИЙ-СЕАНС-ВІДМОВА: ')+Why+#10;
  Err := THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(Line[1],Length(Line)); finally Err.Free end;
end;

begin
  ExitCode := 0;
  if (ParamCount<>1) or
     (RawByteString(ParamStr(1))<>Ukr('--компілювати-фізичний-сеанс')) and
     (RawByteString(ParamStr(1))<>Ukr('--компілювати-фізичний-сеанс-кеш')) and
     (RawByteString(ParamStr(1))<>Ukr('--компілювати-фізичний-сеанс-кеш-2')) and
     (RawByteString(ParamStr(1))<>Ukr('--компілювати-фізичний-сеанс-кеш-4')) then begin
    Fail(Ukr('виклик: senswidesesiiaelf --компілювати-фізичний-сеанс | --компілювати-фізичний-сеанс-кеш | --компілювати-фізичний-сеанс-кеш-2 | --компілювати-фізичний-сеанс-кеш-4'));
    ExitCode := 64;
  end else try
    {$IFNDEF LINUX}
    raise EWideSessionError.Create(Ukr('потрібен Linux'));
    {$ENDIF}
    {$IFNDEF CPUX86_64}
    raise EWideSessionError.Create(Ukr('потрібен x86-64'));
    {$ENDIF}
    if RawByteString(ParamStr(1))=
       Ukr('--компілювати-фізичний-сеанс-кеш-4') then Serve(3)
    else if RawByteString(ParamStr(1))=
            Ukr('--компілювати-фізичний-сеанс-кеш-2') then Serve(2)
    else if RawByteString(ParamStr(1))=
            Ukr('--компілювати-фізичний-сеанс-кеш') then Serve(1)
    else Serve(0);
  except
    on E:Exception do begin
      Fail(RawByteString(E.Message));
      ExitCode := 2;
    end;
  end;
end.
