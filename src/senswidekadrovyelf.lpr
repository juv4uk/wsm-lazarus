{ G6.159 — пакетне AOT без повторного запуску процесу FPC.
  Кадрування LE32 належить виключно host-транспорту, НЕ мові SENS.
  Кожне тіло — незалежна фізична canonical T5M програма; повний
  допуск виконує той самий pinned BuildVerifiedWideELF.
  До завершення перевірки ВСІХ кадрів stdout залишається порожнім. }
program senswidekadrovyelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.irwidefront, wsm.elfgeometry;
const
  MaxFrames = 16;
  MaxPhysicalBytes = 65536;
  MaxImageBytes = 1024 * 1024;
type
  EWideFrameError = class(Exception);
  TNativeImages = array[0..MaxFrames-1] of RawByteString;

function Ukr(const Text: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(Text));
end;

{ Потік — borrowed host descriptor, Data — owned FPC-managed buffer.
  Result=False лише для EOF між кадрами; часткові заголовки й тіла —
  завжди помилка, а не SENS D2-завершення.
  1) Чому короткий read не можна прирівняти до EOF?
  2) Хто звільняє Data, коли всередині циклу виникає виняток?
  3) Чому LE32 не додає до SENS нового домену? }
function ReadExact(Source: TStream; Count: SizeInt; AllowBoundaryEOF: Boolean;
  out Data: RawByteString): Boolean;
var
  Received, N: SizeInt;
begin
  Result := False;
  Data := '';
  if Count < 1 then
    raise EWideFrameError.Create(Ukr('неприпустима довжина host-читання'));
  SetLength(Data, Count);
  Received := 0;
  while Received < Count do begin
    N := Source.Read(Data[Received+1], Count-Received);
    if N < 0 then
      raise EWideFrameError.Create(Ukr('відмова читання фізичного кадру'));
    if N = 0 then begin
      if AllowBoundaryEOF and (Received = 0) then begin
        Data := '';
        Exit(False);
      end;
      raise EWideFrameError.Create(Ukr('обірваний заголовок або фізичне тіло'));
    end;
    Inc(Received, N);
  end;
  Result := True;
end;

{ Header має рівно чотири HOST байти. QWord запобігає переповненню
  signed SizeInt при зловмисному 0xFFFFFFFF. Не розбирає T5M. }
function ReadLength(const Header: RawByteString): QWord;
begin
  if Length(Header) <> 4 then
    raise EWideFrameError.Create(Ukr('немає чотирибайтового заголовка'));
  Result := QWord(Byte(Header[1])) or
            (QWord(Byte(Header[2])) shl 8) or
            (QWord(Byte(Header[3])) shl 16) or
            (QWord(Byte(Header[4])) shl 24);
end;

{ Публікуємо лише готові verified bytes. Після початку host write
  зламаний pipe може мати префікс відповіді; транзакційність stdout
  гарантується тільки для відмов admission ДО першого write.
  1) Чому вихідний кадр не вважається канонічним .sens документом?
  2) Чому весь ELF зберігається до початку запису?
  3) Де обмежено розмір фізичної програми та вихідного образу?
  4) Чи залежать ратифіковані координати від host endian? }
procedure WriteFrame(Target: TStream; const Image: RawByteString);
var
  Header: RawByteString;
  N: QWord;
begin
  N := QWord(Length(Image));
  if (N = 0) or (N > MaxImageBytes) then
    raise EWideFrameError.Create(Ukr('недопустима довжина готового ELF'));
  SetLength(Header, 4);
  Header[1] := AnsiChar(Byte(N and $FF));
  Header[2] := AnsiChar(Byte((N shr 8) and $FF));
  Header[3] := AnsiChar(Byte((N shr 16) and $FF));
  Header[4] := AnsiChar(Byte((N shr 24) and $FF));
  Target.WriteBuffer(Header[1], 4);
  Target.WriteBuffer(Image[1], Length(Image));
end;

{ Усі Images — локальні керовані байтові рядки, owned цим викликом;
  input/output THandleStream обгортають borrowed стандартні дескриптори.
  Семантику, числову драбину D12+ й exact D5/D6 голови перевіряють
  існуючі pinned IR/admission/backend. Жодної назви D7 тут не розбираємо.
  1) Чому сімнадцятий кадр відхиляється до публікації першого?
  2) Чому самостійний T5M документ потрібен у КОЖНОМУ host кадрі?
  3) Як відрізняється перевірка ELF geometry від SENS oracle?
  4) Яка межа щодо кількості алокацій і розміру пакета?
  5) Чому не можна трактувати stderr як фізичну SENS відповідь? }
procedure CompileAll;
var
  Source, Target: THandleStream;
  Header, Physical: RawByteString;
  Images: TNativeImages;
  G: TELFGeometry;
  FrameLength: QWord;
  Count, I: SizeInt;
begin
  Count := 0;
  Source := THandleStream.Create(TextRec(Input).Handle);
  try
    while ReadExact(Source, 4, True, Header) do begin
      FrameLength := ReadLength(Header);
      if (FrameLength < 1) or (FrameLength > MaxPhysicalBytes) then
        raise EWideFrameError.Create(Ukr('довжина T5M кадру поза 1..65536'));
      if Count >= MaxFrames then
        raise EWideFrameError.Create(Ukr('понад 16 незалежних програм'));
      if not ReadExact(Source, SizeInt(FrameLength), False, Physical) then
        raise EWideFrameError.Create(Ukr('немає фізичного T5M тіла'));
      Images[Count] := BuildVerifiedWideELF(Physical, 'external/sens');
      VerifySENSELF64(Images[Count], G);
      if (G.Kind <> 3) or (G.Entry <> 120) or
         (G.FileBytes <> Length(Images[Count])) or
         (Length(Images[Count]) > MaxImageBytes) then
        raise EWideFrameError.Create(Ukr('ELF64 PIE не пройшов допуск'));
      Inc(Count);
    end;
    if Count = 0 then
      raise EWideFrameError.Create(Ukr('порожній набір фізичних кадрів'));
  finally
    Source.Free;
  end;
  Target := THandleStream.Create(TextRec(Output).Handle);
  try
    for I := 0 to Count-1 do WriteFrame(Target, Images[I]);
  finally
    Target.Free;
  end;
end;

procedure Failure(const Msg: RawByteString);
var
  ErrorStream: THandleStream;
  Line: RawByteString;
begin
  Line := Ukr('ШИРОКІ-КАДРИ-ВІДМОВА: ') + Msg + #10;
  ErrorStream := THandleStream.Create(TextRec(ErrOutput).Handle);
  try
    ErrorStream.WriteBuffer(Line[1], Length(Line));
  finally
    ErrorStream.Free;
  end;
end;

begin
  ExitCode := 0;
  if (ParamCount <> 1) or
     (RawByteString(ParamStr(1)) <>
      Ukr('--скомпілювати-фізичні-кадри')) then begin
    Failure(Ukr('виклик: senswidekadrovyelf --скомпілювати-фізичні-кадри < кадри.bin > ельфи.bin'));
    ExitCode := 64;
  end else try
    {$IFNDEF LINUX}
    raise EWideFrameError.Create(Ukr('потрібен Linux'));
    {$ENDIF}
    {$IFNDEF CPUX86_64}
    raise EWideFrameError.Create(Ukr('потрібен x86-64'));
    {$ENDIF}
    CompileAll;
  except
    on E: Exception do begin
      Failure(RawByteString(E.Message));
      ExitCode := 2;
    end;
  end;
end.
