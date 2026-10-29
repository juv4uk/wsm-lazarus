{ G6.120 — повторно використовуваний Linux x86-64 ELF64 для D6:010100
  з двома ДИНАМІЧНИМИ фізичними W12 зі stdin. НЕ новий закон SENS.
  Якір: borrowed цілісний packed .sens D2 вираз pinned D6 «остача».
  Result: owned ET_DYN ELF64 bytes, жодних live pointer у machine.
  Наявний G6.88 BuildD12StreamAddELF забезпечує 6-byte framing,
  канонічний T5M decoder/encoder, reject branch, ELF geometry і writer.
  Змінюємо тільки ОДИН відомий 35-byte x86 ALU фрагмент (той самий
  машинний розмір / усі інші RIP-displacements лишаються дійсними).
  G6.120 профіль: 0≤A≤2047, 1≤B≤2047; негативи fail closed.
  Машина рахує CDQ/IDIV ECX (не Pascal precompute), віддає RDX у EAX.
  1) Чому framed 6 байтів не є одним SENS документом?
  2) Чому фізичний anchor мусить пройти pinned WideIR?
  3) Чому old rel32 на JG можна використати в JLE?
  4) Чому другий rel32 збільшується рівно на три байти?
  5) Чому відсутність overflow correction — лише ВУЗЬКИЙ профіль? }
unit wsm.elfd12restpotik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED12RestStreamError=class(Exception);
function BuildVerifiedD12RestStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwiderest,wsm.elfd12potik,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise ED12RestStreamError.Create(Why);
end;

function BuildVerifiedD12RestStreamELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
const
  HeaderBytes=120;
  { Цей exact template не залежить від назв операцій SENS. }
  OldStart:RawByteString=
    #$44#$89#$C0#$44#$01#$C8#$3D#$FF#$07#0#0#$0F#$8F;
var
  Witness,Replacement:RawByteString;
  Geometry:TELFGeometry;
  P:SizeInt;
  OldSecond,NewSecond:LongInt;
begin
  Result:='';
  { Якір повністю компілюється існуючим verified pinned WideIR.
    Виконуваний kernel після компіляції — 2 opaque runtime D12,
    а НЕ довільний SENS-program decoder. }
  Witness:=BuildIRWideRestELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Witness,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes),
    'неперевірений exact D6 фізичний якір');
  Result:=BuildD12StreamAddELF;
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes),
    'неперевірений механічний stdin/T5M writer');
  P:=Pos(OldStart,Result);
  Need((P>=HeaderBytes+1) and (P+34<=Length(Result)),
    'не знайдено єдиний очікуваний ADD machine slot');
  Need(Pos(OldStart,Copy(Result,P+Length(OldStart),
    Length(Result)))=0,'неоднозначний ADD opcode slot');
  Need(Copy(Result,P+17,7)=#$3D#0#$F8#$FF#$FF#$0F#$8C,
    'змінився шаблон signed lower guard');
  Need(Copy(Result,P+28,7)=#$25#$FF#$0F#0#0#$89#$C3,
    'змінився шаблон фізичного packing');
  { Старий другий JL починався на offset 22 і закінчувався на 28.
    Новий JS починається на offset 19 і закінчується на 25.
    Щоб ОБИДВА переходи вели на той самий reject, новий rel32 = old+3.
    Для першого JG→JLE позиції jump незмінні, disp лишається тим самим. }
  Move(Result[P+24],OldSecond,SizeOf(OldSecond));
  Need((OldSecond>=0) and (OldSecond<=High(LongInt)-3),
    'невідома відстань до fail-closed machine reject');
  NewSecond:=OldSecond+3;
  Replacement:=
    #$44#$89#$C0+              { mov eax,r8d }
    #$99#$90#$90+              { cdq; nop; nop }
    #$44#$89#$C9+              { mov ecx,r9d }
    #$85#$C9+                  { test ecx,ecx }
    #$0F#$8E+Copy(Result,P+13,4)+ { jle 32-bit: B<=0 }
    #$85#$C0#$0F#$88+          { test eax,eax; js A<0 }
    #0#0#0#0+                  { new rel32 at offset 21 }
    #$F7#$F9#$90+              { idiv ecx; nop }
    #$89#$D0#$90#$90#$90+      { mov eax,edx; nop*3 }
    #$89#$C3;                  { mov ebx,eax: old codec expects EBX }
  Need(Length(Replacement)=35,'ALU заміна змінила physical offsets');
  Move(NewSecond,Replacement[22],SizeOf(NewSecond));
  UniqueString(Result);
  Move(Replacement[1],Result[P],Length(Replacement));
  Need(Copy(Result,P+25,2)=#$F7#$F9,
    'машинний IDIV ECX не встановлено');
  Need(Copy(Result,P+28,2)=#$89#$D0,
    'машинна остача не переміщена із RDX');
  Need(Copy(Result,P+11,2)=#$0F#$8E,
    'не встановлено fail-closed B<=0');
  Need(Copy(Result,P+19,2)=#$0F#$88,
    'не встановлено fail-closed A<0');
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
    (Geometry.Entry=HeaderBytes),
    'machine patch пошкодив ELF64 PIE geometry');
end;
end.
