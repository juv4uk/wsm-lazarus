{ G7.9 (задача #655) — ОГЛЯД ЛЕКСИЧНОГО КАДРУ в момент зупину.

  Що тут оглядається і звідки воно береться.
  ------------------------------------------
  Кадри беруться з чинного фізичного механізму wsm.debugtrace (G7.3):
  TDebugTrace уже тримає стек кадрів, кожен із точною доменною
  координатою (ширина + біти) і байтовою позицією в джерелі. Нічого
  нового про «кадр» цей модуль не вигадує.

  Значення беруться з чинного лексичного сховища wsm.envframe (G3.1):
  IEnvFrame.TryResolve шукає точний ключ у своєму кадрі, а якщо не
  знайшов — у батьківському. Тобто «яке значення» і «який батьківський
  кадр» — це не наша інтерпретація, а поведінка самого IEnvFrame.

  Огляд нічого не змінює: жодного InstallLocal, жодного запису в купу,
  жодного нового зв'язування. Це read-only проєкція, як і wsm.uktrace.

  Обмеження, назване чесно: IEnvFrame не має способу піднятися до
  власного батька (ні властивості, ні ітератора). Тому значення
  шукаються через ОДИН переданий кадр — найглибший. Якщо зовнішній
  кадр має те саме слово, що й внутрішній, у поданні буде видно
  внутрішнє значення (звичайне затінення). Батьківський кадр у поданні
  — це структурний батько зі стека TDebugTrace, а не вигаданий.

  Цей модуль НЕ визначає законів SENS: він не вирішує, чи зв'язування
  законне, не рахує значень і не називає домен людиною. Значення в
  кадрі — це opaque QWord-дескриптор, який поклав туди upstream.

  Питання на розуміння саме цього фрагмента:
    1) Чому TOhliadKadru тримає і Key, і ParentIndex, а не покажчик на
       батьківський кадр?
    2) Чому значення шукає найглибший кадр, а не «кадр за індексом»?
    3) Чому Bound=false і Value=0 — це різні твердження, і чому нуль у
       комірці не можна показувати як «не зв'язано»?
    4) Чому огляд не має права викликати InstallLocal навіть для
       «зручності»?
    5) Чому мітки будуються через UTF8Encode, а не літералом? }
unit wsm.lexframe;
{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  SysUtils, wsm.domain, wsm.debugtrace, wsm.envframe;

type
  ELexFrameError = class(Exception);

  { Один оглянутий кадр. Index — людський облік із нуля, 0 = найглибший.
    ParentIndex = -1 означає «батьківського кадру немає». }
  TOhliadKadru = record
    Index: SizeInt;
    Key: TDomainKey;
    ByteOffset, Line, ByteColumn: SizeInt;
    Bound: Boolean;
    Value: QWord;
    ParentIndex: SizeInt;
  end;
  TOhliadKadriv = array of TOhliadKadru;

{ Знімає огляд. Ramka може бути nil: тоді всі зв'язування позначені як
  «значення немає», а кадри все одно показуються — це чесніше, ніж
  вигадувати значення. }
function OhliadLexychnykhKadriv(const Kadry: TDebugFrames;
  const Ramka: IEnvFrame): TOhliadKadriv;

{ Українське подання огляду. Порожній огляд — порожній рядок. }
function OhliadTekstom(const Ohliad: TOhliadKadriv): RawByteString;

{ Точні UTF-8 байти з літерала. FPC згортає кириличний літерал у
  константу типу RawByteString через системну кодову сторінку й робить
  «?»; UTF8Encode(UnicodeString) такого шляху не має. }
function U(const S: UnicodeString): RawByteString;

implementation

var
  MitkaKadr, MitkaDomen, MitkaSlovo, MitkaBajt, MitkaRiadok,
  MitkaStovpets, MitkaZnachennia, MitkaNemaie, MitkaBatko: RawByteString;

function U(const S: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(S);
end;

function OhliadLexychnykhKadriv(const Kadry: TDebugFrames;
  const Ramka: IEnvFrame): TOhliadKadriv;
var
  I, N, Idx: SizeInt;
  Slovo: RawByteString;
  Kadr: TDebugFrame;
  Znach: QWord;
begin
  N := Length(Kadry);
  if N > MaxTraceDepth then
    raise ELexFrameError.Create(U('перевищено межу кількості кадрів'));
  SetLength(Result, N);
  if N = 0 then Exit;
  { Внутрішній масив зберігає кадри від зовнішнього до внутрішнього.
    Людині показуємо найглибший першим; батько — наступний зовнішній. }
  for I := 0 to N - 1 do
  begin
    Kadr := Kadry[N - 1 - I];
    try
      Slovo := KeyBits(Kadr.Key);
    except
      on E: EDomainError do
        raise ELexFrameError.Create(
          U('некоректна фізична координата кадру'));
    end;
    if (Length(Slovo) = 0) or (Kadr.ByteOffset < 1) or
       (Kadr.Line < 1) or (Kadr.ByteColumn < 1) then
      raise ELexFrameError.Create(
        U('некоректні координати або позиція кадру'));
    Idx := I;
    Result[Idx].Index := I;
    Result[Idx].Key := Kadr.Key;
    Result[Idx].ByteOffset := Kadr.ByteOffset;
    Result[Idx].Line := Kadr.Line;
    Result[Idx].ByteColumn := Kadr.ByteColumn;
    Result[Idx].Bound := False;
    Result[Idx].Value := 0;
    if Ramka <> nil then
    begin
      try
        Result[Idx].Bound := Ramka.TryResolve(Kadr.Key, Znach);
      except
        on E: EFrameError do
          raise ELexFrameError.Create(
            U('кадр відмовив у пошуку координати'));
      end;
      if Result[Idx].Bound then
        Result[Idx].Value := Znach;
    end;
    if I + 1 < N then Result[Idx].ParentIndex := I + 1
    else Result[Idx].ParentIndex := -1;
  end;
end;

function OhliadTekstom(const Ohliad: TOhliadKadriv): RawByteString;
var
  I: SizeInt;
  Slovo, Znachennia, Batko: RawByteString;
begin
  Result := '';
  if Length(Ohliad) > MaxTraceDepth then
    raise ELexFrameError.Create(U('перевищено межу кількості кадрів'));
  for I := 0 to High(Ohliad) do
  begin
    Slovo := KeyBits(Ohliad[I].Key);
    if Ohliad[I].Bound then
      Znachennia := RawByteString(IntToStr(Ohliad[I].Value))
    else
      Znachennia := MitkaNemaie;
    if Ohliad[I].ParentIndex >= 0 then
      Batko := RawByteString(IntToStr(Ohliad[I].ParentIndex))
    else
      Batko := MitkaNemaie;
    Result := Result + MitkaKadr + ' ' +
      RawByteString(IntToStr(Ohliad[I].Index)) +
      ': ' + MitkaDomen + ' D' +
      RawByteString(IntToStr(Ohliad[I].Key.Width)) +
      ', ' + MitkaSlovo + ' ' + Slovo +
      ', ' + MitkaBajt + ' ' +
      RawByteString(IntToStr(Ohliad[I].ByteOffset)) +
      ', ' + MitkaRiadok + ' ' +
      RawByteString(IntToStr(Ohliad[I].Line)) +
      ', ' + MitkaStovpets + ' ' +
      RawByteString(IntToStr(Ohliad[I].ByteColumn)) +
      ', ' + MitkaZnachennia + ' ' + Znachennia +
      ', ' + MitkaBatko + ' ' + Batko + #10;
  end;
end;

initialization
  MitkaKadr := U('кадр');
  MitkaDomen := U('домен');
  MitkaSlovo := U('слово');
  MitkaBajt := U('байт');
  MitkaRiadok := U('рядок');
  MitkaStovpets := U('стовпець');
  MitkaZnachennia := U('значення');
  MitkaNemaie := U('немає');
  MitkaBatko := U('батько');

end.
