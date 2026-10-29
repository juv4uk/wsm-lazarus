{ G6.33. Незалежний структурний admission ВЖЕ згенерованого Linux ELF64.
  Це вузький профіль нинішніх SENS emitters: одна RX PT_LOAD без
  relocation/sections. Не декодує машинних інструкцій, D7 або закони. }
unit wsm.elfgeometry;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  EELFGeometryError=class(Exception);
  TELFGeometry=record
    Kind:Word; { host ELF ET_EXEC=2 / ET_DYN=3, НЕ домен SENS }
    Entry:QWord;
    SegmentBase:QWord;
    FileBytes:SizeInt;
    MachineBytes:SizeInt;
  end;
procedure VerifySENSELF64(const Image:RawByteString;out Geometry:TELFGeometry);
implementation
const
  FixedHeaderBytes=120; { ELF header 64 + один program header 56 }
  MaxNativeImageBytes=1024*1024; { host квота, не мовний закон }

procedure VerifySENSELF64(const Image:RawByteString;out Geometry:TELFGeometry);
var
  Candidate:TELFGeometry;
  I:SizeInt;
  Base,Kind,Entry:QWord;
  function LE(Offset,Count:SizeInt):QWord;
  var J:SizeInt;
  begin
    if (Offset<0) or (Count<1) or (Count>8) or
      (Offset>Length(Image)-Count) then
      raise EELFGeometryError.Create('Поле ELF поза фізичними байтами');
    Result:=0;
    for J:=Count-1 downto 0 do
      Result:=(Result shl 8) or QWord(Byte(Image[Offset+J+1]));
  end;
  procedure Guard(OK:Boolean;const Why:UnicodeString);
  begin
    if not OK then
      raise EELFGeometryError.Create(UTF8Encode(Why));
  end;
begin
  { Усі поля вихідної статистики залишаються НУЛЕМ аж до успіху,
    навіть після пізньої помилки. Image borrowed, ніколи не змінюється. }
  FillChar(Geometry,SizeOf(Geometry),0);
  FillChar(Candidate,SizeOf(Candidate),0);
  Guard((Length(Image)>FixedHeaderBytes) and
        (Length(Image)<=MaxNativeImageBytes),
        'Непридатна фізична довжина ELF');
  Guard(Copy(Image,1,4)=#$7F'ELF','Непридатна магія ELF');
  Guard((LE(4,1)=2) and (LE(5,1)=1) and (LE(6,1)=1),
    'Потрібні ELF64, little endian та версія ident=1');
  for I:=7 to 15 do
    Guard(LE(I,1)=0,'Неприпустимий OSABI чи резерв ident');
  Kind:=LE(16,2);
  Guard((Kind=2) or (Kind=3),'Не підтримано тип ELF');
  Guard((LE(18,2)=62) and (LE(20,4)=1),
    'Потрібні ELF x86-64 та версія 1');
  Entry:=LE(24,8);
  Guard((LE(32,8)=64) and (LE(40,8)=0) and (LE(48,4)=0),
    'Потрібен єдиний program-header без section-table і flags');
  Guard((LE(52,2)=64) and (LE(54,2)=56) and
        (LE(56,2)=1) and (LE(58,2)=0) and
        (LE(60,2)=0) and (LE(62,2)=0),
    'Невірні розміри або кількість ELF header/section');
  Guard((LE(64,4)=1) and (LE(68,4)=5),
    'Єдиний PT_LOAD має бути лише читання/виконання (RX)');
  Guard(LE(72,8)=0,'Сегмент мусить починатись від нульового file offset');
  if Kind=2 then Base:=$400000 else Base:=0;
  Guard((LE(80,8)=Base) and (LE(88,8)=Base),
    'Адреси ELF segment vaddr/paddr не відповідають профілю');
  Guard((LE(96,8)=QWord(Length(Image))) and
        (LE(104,8)=QWord(Length(Image))),
    'PT_LOAD filesz/memsz не відповідає цілому фізичному ELF');
  Guard(LE(112,8)=$1000,'Непідтримане вирівнювання PT_LOAD');
  Guard(Entry=Base+FixedHeaderBytes,
    'Entry не відповідає першій фізичній машинній інструкції');
  { Не дозволяємо aliasing секцій/segment payload, чия геометрія
    випадково допустима по окремих полях, але за межами образу. }
  Guard((Entry>=Base) and
        ((Entry-Base)<QWord(Length(Image))) and
        (QWord(Length(Image)-FixedHeaderBytes)>=1),
        'Точка входу не належить виконуваному сегменту');

  Candidate.Kind:=Word(Kind);
  Candidate.Entry:=Entry;
  Candidate.SegmentBase:=Base;
  Candidate.FileBytes:=Length(Image);
  Candidate.MachineBytes:=Length(Image)-FixedHeaderBytes;
  Geometry:=Candidate;
end;

{ Пам'ять: Image borrowed незмінний RawByteString; Candidate на стеку;
  out Geometry очищається до перевірок, заповнюється атомарно.
  Ні алокації машинної пам'яті, ні виконання ELF у цьому unit.
  Питання:
  1) Чому ET_EXEC і ET_DYN мають різні p_vaddr, а не мовні Dn?
  2) Чому e_entry перевіряємо разом з PT_LOAD, а не окремо?
  3) Чому p_filesz і p_memsz мають збігатися з усім байтовим образом?
  4) Чому цей guard не підтверджує семантику D3/REPL SENS?
  5) Чому D7 SYN залишається фізичними даними навіть у ELF? }
end.
