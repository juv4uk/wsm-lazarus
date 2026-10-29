{ G6.75 — host компілятор двох фізичних D12 атомів в D1 CMP/SETL ELF.
  Слово мови D5:11010 і вся числова семантика належать pinned SENS.
  --менше-D12 — explicit host selection, НЕ D7 textual dispatch. }
program sensd12mensheelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12less,wsm.elfpublish,wsm.elfgeometry;
const
  ModeLess:RawByteString='--'+#$D0#$BC#$D0#$B5#$D0#$BD#$D1#$88#$D0#$B5+'-D12';
type ECLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — borrowed host шлях, результат owned T5M, FPC managed bytes.
  Розмір — лише ресурсна межа, домен перевіряє wsm.numericplane.
  1) Чому .lisp відхилено? 2) Чому share-deny-write?
  3) Хто встановлює домен, а хто лише відкриває файл? }
function ReadFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ECLI.Create(UA('потрібен canonical двійковий .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ECLI.Create(UA('неприпустима довжина фізичного атома'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Status — host UTF-8, не SENS T5M. Успіх публікується тільки
  після повної перевірки ELF і no-clobber атомарного файла.
  1) Чому status не є фізичною відповіддю?
  2) Хто забезпечує відсутність перезапису?
  3) Чому всі managed bytes існують до завершення Run? }
procedure EmitText(Handle:THandle;const Bytes:RawByteString);
var S:THandleStream;
begin
  S:=THandleStream.Create(Handle);
  try
    if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;

procedure Run;
var A,B,ELF:RawByteString; G:TELFGeometry;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>ModeLess) then
    raise ECLI.Create(UA('виклик: sensd12mensheelf --менше-D12 ліве.sens праве.sens новий.elf'));
  if ExtractFileExt(ParamStr(4))<>'.elf' then
    raise ECLI.Create(UA('вихід має бути новим .elf'));
  {$IFNDEF LINUX}
    raise ECLI.Create(UA('потрібен Linux'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
    raise ECLI.Create(UA('потрібен x86-64'));
  {$ENDIF}
  A:=ReadFile(ParamStr(2)); B:=ReadFile(ParamStr(3));
  ELF:=BuildD12LessELF(A,B);
  PublishNewELF64(ParamStr(4),ELF,3,G);
  EmitText(TextRec(Output).Handle,
    UA('ELF-D12-МЕНШЕ-ГОТОВО байтів=')+IntToStr(G.FileBytes)+
    UA(' тип=')+IntToStr(G.Kind)+' machine=CMP/SETL stdout=T5M'+#10);
end;

begin
  try Run
  except on E:Exception do begin
    EmitText(TextRec(ErrOutput).Handle,
      UA('ELF-D12-МЕНШЕ-ВІДМОВА: ')+UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.

{ Цей CLI ніколи не визначає D5/D12 законів, не отримує SENS
  операції з назви .lisp і не виконує Lisp eval/apply.
  1) Чому тут немає локальної таблиці числових функцій?
  2) Де виконуються CMP/SETL?
  3) Як гарантується canonical D1:0 чи D1:1?
  4) Чи є це загальним компілятором? (Ні.) }
