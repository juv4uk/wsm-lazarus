{ G6.9: справжній ELF64/x86-64 Linux для кількох НЕЗАЛЕЖНИХ D1 коренів.
  Єдине джерело мовних законів — pinned SENS: чинні T5M/D2,
  exact-domain binder і TBinaryExecutor. Жодного власного dispatch.
  Цей приватний ELF — машинний артефакт, НЕ канонічний .sens. }
unit wsm.elfbatch;
{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils;

const MaxELFBatchRoots = 1024;

type EELFBatchError = class(Exception);

function BuildD1BatchELF(const Physical, AuthorityRoot: RawByteString):RawByteString;

implementation

uses wsm.t5m, wsm.d2source, wsm.bind, wsm.domain,
  wsm.binarybind, wsm.binaryexec;

const
  ELFBase:QWord = $400000;
  HeaderBytes = 64 + 56;
  OneWriteBytes = 24;
  ExitBytes = 9;

function UkrBytes(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

function BuildD1BatchELF(const Physical, AuthorityRoot:RawByteString):RawByteString;
var
  ExactWords, SingleWord:TExactWords;
  Document:TD2Document;
  Domains:TDomainSet;
  Bound:TBinaryWords;
  Executor:TBinaryExecutor;
  Digits, Bits, Witness:RawByteString;
  I, J, N, FileSize, DataOffset, CodePos, Displacement:SizeInt;

  procedure Put(Offset:SizeInt; Number:QWord; Count:SizeInt);
  var K:SizeInt;
  begin
    { Внутрішні константні межі обчислені тільки після повного admission. }
    if (Offset<0) or (Count<0) or
       (Offset>Length(Result)-Count) then
      raise EELFBatchError.Create(UkrBytes('Помилка внутрішнього розміру ELF'));
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(Number and $FF));
      Number:=Number shr 8;
    end;
  end;

begin
  Result:='';
  Document:=nil;
  Executor:=nil;
  try
    try
      { Точно один decode; потім безпосередній D2 parse, ніякого .lisp. }
      DecodeT5M(Physical,ExactWords);
      if EncodeT5M(ExactWords)<>Physical then
        raise EELFBatchError.Create(UkrBytes('Неканонічні фізичні байти T5M'));
      Document:=ParseD2Words(ExactWords);
      N:=Length(Document.Roots);
      if (N<1) or (N>MaxELFBatchRoots) then
        raise EELFBatchError.Create(UkrBytes('Кількість фізичних коренів має бути від 1 до 1024'));

      LoadPinnedDomains(AuthorityRoot,Domains);
      BindD2Binary(Document,Domains,Bound);
      if Length(Bound)<>N then
        raise EELFBatchError.Create(UkrBytes('Підтримано лише одиничні фізичні D1 атоми'));

      SetLength(Digits,N);
      for I:=0 to N-1 do begin
        if (Document.Roots[I]=nil) or
           (Document.Roots[I].Kind<>dkIdentity) or
           (Document.Roots[I].Width<>1) or
           (Bound[I].Key.Width<>1) or
           (Bound[I].RootIndex<>I) or
           (Bound[I].WordIndex<>Document.Roots[I].WordIndex) or
           Bound[I].IsEmpty then
          raise EELFBatchError.Create(UkrBytes('Непідтверджена структура кореня D1: форма ')+IntToStr(I+1));
        Bits:=KeyBits(Bound[I].Key);
        if ((Bits<>'0') and (Bits<>'1')) or
           (Document.Roots[I].Bits<>Bits) then
          raise EELFBatchError.Create(UkrBytes('Непідтверджене точне двійкове слово D1: форма ')+IntToStr(I+1));
        Digits[I+1]:=Bits[1];
      end;

      { Всі корені й pinned binder допущено ДО першого виконання.
        Той самий існуючий фізичний evaluator — не нове тлумачення. }
      Executor:=TBinaryExecutor.Create(AuthorityRoot);
      SetLength(SingleWord,1);
      for I:=0 to N-1 do begin
        SingleWord[0]:=RawByteString(Digits[I+1]);
        Witness:=Executor.ExecutePhysical(EncodeT5M(SingleWord));
        if Witness<>SingleWord[0] then
          raise EELFBatchError.Create(UkrBytes('Нативний D1 не збігається із чинним виконавцем: форма ')+IntToStr(I+1));
      end;

      { Один sys_write для КОЖНОГО кореня: це виконувані x86-64
        машинні інструкції, не FPC runtime, оболонка або echo-loop.
        Кожна LEA адресує власний байт даних, після неї наступний RIP
        має адресу CodePos+17. Для 1 кореня ELF байт-у-байт G6.8. }
      DataOffset:=HeaderBytes+OneWriteBytes*N+ExitBytes;
      FileSize:=DataOffset+2*N;
      SetLength(Result,FileSize);
      FillChar(Result[1],FileSize,0);

      { ELF64: little endian, ET_EXEC, EM_X86_64, один RX PT_LOAD. }
      Put(0,$464C457F,4);
      Put(4,2,1); Put(5,1,1); Put(6,1,1);
      Put(16,2,2); Put(18,62,2); Put(20,1,4);
      Put(24,ELFBase+HeaderBytes,8); Put(32,64,8);
      Put(52,64,2); Put(54,56,2); Put(56,1,2);
      Put(64,1,4); Put(68,5,4);
      Put(80,ELFBase,8); Put(88,ELFBase,8);
      Put(96,FileSize,8); Put(104,FileSize,8); Put(112,$1000,8);

      for I:=0 to N-1 do begin
        CodePos:=HeaderBytes+OneWriteBytes*I;
        Displacement:=(DataOffset+2*I)-(CodePos+17);
        { mov eax,1; mov edi,1; lea rsi,[rip+disp32];
          mov edx,2; syscall. Увесь disp32 додатний у ліміті N. }
        Put(CodePos,$00000001B8,5);
        Put(CodePos+5,$00000001BF,5);
        Put(CodePos+10,$358D48,3);
        Put(CodePos+13,Displacement,4);
        Put(CodePos+17,$00000002BA,5);
        Put(CodePos+22,$050F,2);
        Result[DataOffset+2*I+1]:=Digits[I+1];
        Result[DataOffset+2*I+2]:=#10;
      end;
      { mov eax,60; xor edi,edi; syscall — Linux exit(0). }
      J:=HeaderBytes+OneWriteBytes*N;
      Put(J,$0000003CB8,5);
      Put(J+5,$050FFF31,4);
    except
      on E:EELFBatchError do raise;
      on E:Exception do
        raise EELFBatchError.Create(UkrBytes('Нативний багатокореневий допуск відхилено: ')+E.Message);
    end;
  finally
    Executor.Free;
    Document.Free;
  end;
end;

end.
