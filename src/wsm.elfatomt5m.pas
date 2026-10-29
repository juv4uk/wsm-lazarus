{ G6.27 — фізичний T5M-вихід машинної D3:010 «атом?».
  Мовна влада належить pinned SENS Contract 12, admission — BuildAtomELF.
  Міняємо ВИКЛЮЧНО stdout host-transport, а не D3, D12+ чи викличність.
  Результат 0/1 обчислюється машинними AND/CMP/SETNE/MOVZX, не Pascal. }
unit wsm.elfatomt5m;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfAtomT5MError=class(Exception);
function BuildAtomT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.elfatom,wsm.t5m;

const
  HeaderBytes=120; { існуючий ELF64 ET_EXEC: ELF header 64 + PHDR 56 }
  { Перевірений host stdout суфікс BuildAtomELF:
    тег 1/2 → ASCII '0'/'1' та LF, write(1,2), exit(0).
    Відмовляємо, якщо інший агент змінить машинний ABI/емітер. }
  OldSuffix=
    #$83#$E8#$01#$04#$30+
    #$48#$83#$EC#$08#$88#$04#$24+
    #$C6#$44#$24#$01#$0A+
    #$B8#$01#0#0#0+#$BF#$01#0#0#0+
    #$48#$89#$E6+#$BA#$02#0#0#0+
    #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF#$0F#$05;

function BuildAtomT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Image,NewSuffix,EncodedZero,EncodedOne:RawByteString;
    Words:TExactWords;
    I,PrefixBytes,Total:SizeInt;
    Delta:Byte;

  function ReadQWord(const B:RawByteString;Off:SizeInt):QWord;
  var J:SizeInt;
  begin
    if (Off<0) or (Off>Length(B)-8) then
      raise EElfAtomT5MError.Create('Зламана довжина ELF64');
    Result:=0;
    for J:=7 downto 0 do
      Result:=(Result shl 8) or QWord(Ord(B[Off+J+1]));
  end;

  procedure PutQWord(Off:SizeInt;V:QWord);
  var J:SizeInt;
  begin
    if (Off<0) or (Off>Length(Result)-8) then
      raise EElfAtomT5MError.Create('Зламана межа ELF64');
    for J:=0 to 7 do begin
      Result[Off+J+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

begin
  Result:='';
  try
    { Успадкувати ВЕСЬ поточний admission фізичних форм D3:010,
      фактичні CONS-комірки, pinned binder і перевірене виконання.
      Від чужого emitter не копіюємо закони в Pascal. }
    Image:=BuildAtomELF(Physical,AuthorityRoot);
    if Length(Image)<HeaderBytes+Length(OldSuffix) then
      raise EElfAtomT5MError.Create('Неповний ELF64 від D3:010');
    if (Copy(Image,1,4)<>#$7F'ELF') or (Ord(Image[5])<>2) or
       (Ord(Image[17])<>2) or (Ord(Image[19])<>62) or
       (ReadQWord(Image,96)<>QWord(Length(Image))) or
       (ReadQWord(Image,104)<>QWord(Length(Image))) or
       (Copy(Image,Length(Image)-Length(OldSuffix)+1,
         Length(OldSuffix))<>OldSuffix) then
      raise EElfAtomT5MError.Create('Змінився перевірений D3:010 ELF ABI');

    { Два точні результати D1:0, D1:1 як ОДНЕ фізичне слово.
      Жодних hard-coded базових тритів чи ASCII. }
    SetLength(Words,1);
    Words[0]:='0';EncodedZero:=EncodeT5M(Words);
    Words[0]:='1';EncodedOne:=EncodeT5M(Words);
    if (Length(EncodedZero)<>1) or (Length(EncodedOne)<>1) then
      raise EElfAtomT5MError.Create('Змінено однобайтовий T5M D1');
    if (Ord(EncodedOne[1])<=Ord(EncodedZero[1])) or
       (Ord(EncodedOne[1])-Ord(EncodedZero[1])>127) then
      raise EElfAtomT5MError.Create('T5M D1 різниця поза машинною межею');
    Delta:=Ord(EncodedOne[1])-Ord(EncodedZero[1]);

    { Вхід: EAX=1 або 2, результат реальних ATOM інструкцій.
      sub eax,1 → 0/1; imul eax,eax,Delta; add al,EncodedZero;
      запис AL у стек і Linux write(1,1). Жодного LF.
      Це transport T5M, НЕ D12+ числова операція. }
    NewSuffix:=
      #$83#$E8#$01+#$6B#$C0+AnsiChar(Delta)+#$04+EncodedZero[1]+
      #$48#$83#$EC#$08+#$88#$04#$24+
      #$B8#$01#0#0#0+#$BF#$01#0#0#0+
      #$48#$89#$E6+#$BA#$01#0#0#0+
      #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF#$0F#$05;
    PrefixBytes:=Length(Image)-Length(OldSuffix);
    Total:=PrefixBytes+Length(NewSuffix);
    if (Total<=HeaderBytes) or (Total>HeaderBytes+2048) then
      raise EElfAtomT5MError.Create('Вийшли за межі машинного коду');
    SetLength(Result,Total);
    for I:=1 to PrefixBytes do Result[I]:=Image[I];
    for I:=1 to Length(NewSuffix) do
      Result[PrefixBytes+I]:=NewSuffix[I];
    { RX PT_LOAD: розмір файла і машинного образу змінюються разом;
      entry=0x400000+120 і поточний базовий код не змінюються. }
    PutQWord(96,QWord(Total));
    PutQWord(104,QWord(Total));
  except
    on E:EElfAtomT5MError do raise;
    on E:Exception do raise EElfAtomT5MError.Create(
      'Фізичний машинний ATOM не допущено: '+E.Message);
  end;
end;

{ Питання: 1) Чому BuildAtomELF лишається єдиним admission?
  2) Чому Tag=1/2 не є SENS числовим значенням?
  3) Чому машинний imul залежить лише від двох EncodeT5M виходів?
  4) Чому byte-count у write і p_filesz потрібно міняти одночасно?
  5) Чому зміна машинного stdout не дає нового закону D3? }
end.
