{ G6.9 — машинний ELF64 для 2..256 незалежних D1 коренів.
  Вся семантика допуску і код ELF64 одного літерала походять
  з чинного wsm.elfd1. Цей механізм з'єднує лише перевірені
  фізичні відповіді й збільшує sys_write довжину даних.
  ELF — нативний артефакт Linux, НЕ канонічний .sens і НЕ Core4. }
unit wsm.elfd1batch;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;

const
  MinNativeD1Roots = 2;
  MaxNativeD1Roots = 256;
type
  EELFD1BatchError = class(Exception);
function BuildD1BatchELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.elfd1, wsm.binarybatch, wsm.binaryexec;

const
  HeaderAndCodeBytes = 153; { G6.8 ELF 64+56+33; без payload }
  PayloadBase = HeaderAndCodeBytes;
  ELFHeaderFileSizeOffset = 96; { RX PT_LOAD p_filesz }
  ELFHeaderMemorySizeOffset = 104; { RX PT_LOAD p_memsz }
  WriteLengthOffset = 138; { code 120 + mov edx,imm32 argument at 18 }

procedure PutLE(var Bytes: RawByteString;
  Offset: SizeInt; Number: QWord; Count: SizeInt);
var I: SizeInt;
begin
  if (Offset < 0) or (Count < 1) or (Count > 8) or
     (Offset > Length(Bytes) - Count) then
    raise EELFD1BatchError.Create('неможливо записати поле ELF');
  for I := 0 to Count-1 do begin
    Bytes[Offset+I+1] := AnsiChar(Byte(Number and $FF));
    Number := Number shr 8;
  end;
end;

function BuildD1BatchELF(const Physical, AuthorityRoot: RawByteString):
  RawByteString;
var
  Doc: TD2Document;
  RootWords: TExactWords;
  Executor: TBinaryExecutor;
  Answers: TBinaryBatchAnswers;
  Sample, Template, Bits: RawByteString;
  I, N, TotalBytes: SizeInt;
begin
  Result := '';
  Doc := nil;
  Executor := nil;
  try
    try
      { Перший повний T5M/D2 допуск, без власного розбору байтів. }
      Doc := ReadD2T5M(Physical);
      N := Length(Doc.Roots);
      if (N < MinNativeD1Roots) or (N > MaxNativeD1Roots) then
        raise EELFD1BatchError.Create(
          'нативний пакет вимагає 2..256 незалежних фізичних D1 форм');
      { Підтвердження ВСЬОГО документа чинним обчислювачем ще до
        будь-якого породження машини. Повертає лише host bytes. }
      Executor := TBinaryExecutor.Create(AuthorityRoot);
      ExecuteBinaryBatch(Physical, Executor, Answers, MaxNativeD1Roots*2);
      if Length(Answers) <> N then
        raise EELFD1BatchError.Create('кількість підтверджених відповідей');
      SetLength(RootWords, 1);
      Template := '';
      for I := 0 to N-1 do begin
        if (Doc.Roots[I] = nil) or (Doc.Roots[I].Kind <> dkIdentity) or
           (Doc.Roots[I].Width <> 1) then
          raise EELFD1BatchError.Create(
            'непідтверджена фізична форма: допускаються лише D1');
        Bits := Doc.Roots[I].Bits;
        if (Bits <> '0') and (Bits <> '1') then
          raise EELFD1BatchError.Create('непідтверджені біти фізичного D1');
        if Answers[I] <> Bits then
          raise EELFD1BatchError.Create(
            'пакетний виконавець повернув іншу фізичну відповідь');
        RootWords[0] := Bits;
        { Повторно використовуємо ТОЙ САМИЙ G6.8 ELF backend:
          він робить pinned BindD2Binary і перевіряє відповідь
          незалежним single-root ExecutePhysical. }
        Sample := BuildD1ELF(EncodeT5M(RootWords), AuthorityRoot);
        if (Length(Sample) <> HeaderAndCodeBytes+2) or
           (Sample[154] <> Bits[1]) or (Sample[155] <> #10) then
          raise EELFD1BatchError.Create('G6.8 не підтвердив машинний шаблон');
        if I = 0 then Template := Sample
        else if Copy(Sample, 1, HeaderAndCodeBytes) <>
                Copy(Template, 1, HeaderAndCodeBytes) then
          raise EELFD1BatchError.Create(
            'різні машинні шаблони чинного G6.8 backend');
      end;
      TotalBytes := PayloadBase + N*2;
      SetLength(Result, TotalBytes);
      Move(Template[1], Result[1], HeaderAndCodeBytes);
      { Міняються ЛИШЕ фізична довжина ELF і mov edx=payload length.
        Інструкції sys_write/sys_exit — побайтно шаблон G6.8. }
      PutLE(Result, ELFHeaderFileSizeOffset, QWord(TotalBytes), 8);
      PutLE(Result, ELFHeaderMemorySizeOffset, QWord(TotalBytes), 8);
      PutLE(Result, WriteLengthOffset, QWord(N*2), 4);
      for I := 0 to N-1 do begin
        Result[PayloadBase+I*2+1] := Answers[I][1];
        Result[PayloadBase+I*2+2] := #10;
      end;
    except
      on E: EELFD1BatchError do raise;
      on E: Exception do raise EELFD1BatchError.Create(
        'фізичний D1 ELF пакет відхилено: ' + E.Message);
    end;
  finally
    Executor.Free;
    Doc.Free;
  end;
end;

end.
