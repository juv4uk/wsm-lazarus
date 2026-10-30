{ G6.28. Вузька нативна компіляція цитованої фізичної D3:001 форми.
  Літерал підтверджено ЧИННИМ pinned D3 runtime; машинний ELF лише
  зберігає його точні T5M-байти і записує їх через Linux x86-64 syscall.
  Це не власна інтерпретація QUOTE, не загальний compiler і не SENS oracle. }
unit wsm.elfquotet5m;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EELFQuoteT5MError=class(Exception);
function BuildQuoteT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.d2source,wsm.binarybind,wsm.bind,wsm.domain,wsm.binaryexec;

const
  HeaderBytes=120; { ELF64=64 + один ProgramHeader=56 }
  MaxLiteralBytes=4096; { виключно ресурсний host ліміт }

function BuildQuoteT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  Exact,Returned:TExactWords;
  Answer,Machine:RawByteString;
  Head:TD2Node;
  I,Total,DataOffset,Displacement:SizeInt;

  procedure Reject(const Why:String);
  begin raise EELFQuoteT5MError.Create(Why); end;

  procedure PutLE(Off:SizeInt;V:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    if (Off<0) or (Count<1) or (Count>8) or
       (Off>Length(Result)-Count) then
      Reject('Пошкоджено межі поля ELF64');
    for J:=0 to Count-1 do begin
      Result[Off+J+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

begin
  Result:='';Doc:=nil;Engine:=nil;
  try
    try
      if (Length(Physical)<1) or (Length(Physical)>65536) then
        Reject('Фізичне джерело поза host-межею');
      DecodeT5M(Physical,Exact);
      if EncodeT5M(Exact)<>Physical then
        Reject('Неканонічний T5M');
      Doc:=ParseD2Words(Exact);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) or
         (Length(Doc.Roots[0].Children)<>2) or
         (Length(Bound)<1) then
        Reject('Потрібна одна фізична форма з одним аргументом');
      Head:=Doc.Roots[0].Children[0];
      if (Head=nil) or (Head.Kind<>dkIdentity) or
         (Head.Width<>3) or (Head.Bits<>'001') or
         (Bound[0].RootIndex<>0) or
         (Bound[0].WordIndex<>Head.WordIndex) or
         (Bound[0].Key.Width<>3) or
         (KeyBits(Bound[0].Key)<>'001') or Bound[0].IsEmpty then
        Reject('Голова не є точним pinned D3:001');
      { Єдиний власник обчислення цитованого значення — чинний
        binary executor з exact-domain binder, без нового dispatch. }
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysicalT5M(Physical);
      if (Length(Answer)<1) or (Length(Answer)>MaxLiteralBytes) then
        Reject('Фізичний літерал поза host-межею');
      DecodeT5M(Answer,Returned);
      if EncodeT5M(Returned)<>Answer then
        Reject('Runtime не повернув канонічний T5M');

      { Linux x86-64 ET_DYN, жодних relocation:
          mov eax,1; mov edi,1; lea rsi,[rip+disp32];
          mov edx,Length(Answer); syscall; cmp rax,rdx;
          jne exit(2); exit(0) лише після повного фізичного запису.
        Дані розташовано відразу після машинних 50 байтів.
        Байти літерала не декодуються в числа або назви. }
      Machine:=
        #$B8#$01#0#0#0 + #$BF#$01#0#0#0 +
        #$48#$8D#$35#0#0#0#0 + #$BA#0#0#0#0 +
        #$0F#$05 + #$48#$39#$D0 + #$75#$09 +
        #$B8#$3C#0#0#0 + #$31#$FF + #$0F#$05 +
        #$B8#$3C#0#0#0 + #$BF#$02#0#0#0 + #$0F#$05;
      { Linux syscall зберігає RDX=точний розмір фізичного T5M,
        а RAX містить записані байти або від'ємний -errno.
        Немає exit(0), поки весь байтовий літерал не опубліковано.
        Код 2 — host-відмова, НЕ SENS D1/значення.
        1) Чому порівнюємо RAX саме з RDX?
        2) Чому короткий запис не є успішною цитатою?
        3) Хто володіє машинним буфером Machine?
        4) Як обчислюється RIP displacement після розширення?
        5) Чому це не нове правило D3? }
      if Length(Machine)<>50 then Reject('Змінився перевірений x86-64 шаблон');
      DataOffset:=HeaderBytes+Length(Machine);
      Displacement:=DataOffset-(HeaderBytes+17);
      if (Displacement<0) or (Displacement>High(LongInt)) then
        Reject('RIP-відносна адреса поза межами');
      Total:=DataOffset+Length(Answer);
      if Total>HeaderBytes+Length(Machine)+MaxLiteralBytes then
        Reject('Перевищено ELF host-ліміт');
      SetLength(Result,Total);
      FillChar(Result[1],Total,0);
      { ELF64 ET_DYN, EM_X86_64, один RX PT_LOAD; entry=120. }
      PutLE(0,$464C457F,4);
      PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
      PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4);
      PutLE(24,HeaderBytes,8);PutLE(32,64,8);
      PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
      PutLE(64,1,4);PutLE(68,5,4);
      PutLE(80,0,8);PutLE(88,0,8);
      PutLE(96,Total,8);PutLE(104,Total,8);PutLE(112,$1000,8);
      for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
      PutLE(HeaderBytes+13,QWord(Displacement),4); { lea RIP+16 }
      PutLE(HeaderBytes+18,QWord(Length(Answer)),4); { write length }
      for I:=1 to Length(Answer) do Result[DataOffset+I]:=Answer[I];
    except
      on E:EELFQuoteT5MError do begin Result:='';raise; end;
      on E:Exception do begin
        Result:='';
        raise EELFQuoteT5MError.Create('Нативну цитату відхилено: '+E.Message);
      end;
    end;
  finally
    Engine.Free;
    Doc.Free;
  end;
end;

{ Питання для перевірки:
  1. Чому літерал проходить через чинний D3 executor до генерації?
  2. Чому машинні дані — саме T5M, а не Unicode/десяткове число?
  3. Чому RIP+disp32 забезпечує незалежність від базової адреси ET_DYN?
  4. Чому D12 не можна вивести із ширини цитованого D7?
  5. Чому цей машинний зріз ще не є загальним compiler Core4? }
end.
