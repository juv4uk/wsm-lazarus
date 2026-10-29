{ G3.48 — повні фізичні D7-імена Core1 у pinned людській проєкції укр.
  Єдині джерела: TCore1Index з canonical core1.sens і wsm.d7text з
  pinned d7.lisp. Текст НЕ визначає закон і НЕ доводить викличність. }
program senscore1nazvy;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.core1index, wsm.d7text;

const
  MaxNames=256;
  MaxGlyphs=256;

{ Root — лише запозичений шлях host. FPC-managed Result — повний список
  UTF-8 проєкцій, сформований після фізичного admission усіх DEFINE.
  TCore1Index володіє точними D7 бітами; Map — короткоживуча копія pinned
  D7 таблиці; жодне ім'я не призначає операторові мовного закону.
  Питання: чому ширина W7 не є Unicode? Хто володіє Index?
  Чому повний список публікується тільки після всіх 96 перевірок?
  Чому зворотне кодування звіряється побайтово? }
function BuildNames(const Root:String):RawByteString;
var
  Index:TCore1Index;
  Map:TD7Map;
  Def:TCore1Definition;
  Words:TExactWords;
  Bits,Physical,Name,Back,Report:RawByteString;
  I,J,Glyphs:SizeInt;
begin
  Result:='';
  Report:='';
  Index:=nil;
  try
    LoadPinnedD7Map(Root,Map);
    Index:=TCore1Index.Create(Root);
    if (Index.Count<1) or (Index.Count>MaxNames) then
      raise Exception.Create('кількість фізичних DEFINE поза межею');
    for I:=1 to Index.Count do begin
      Def:=Index.Definition(I);
      Bits:=Def.NameBits;
      if (Length(Bits)<7) or
         (Length(Bits)>MaxGlyphs*7) or
         ((Length(Bits) mod 7)<>0) then
        raise Exception.Create('фізичне ім’я не є послідовністю D7');
      Glyphs:=Length(Bits) div 7;
      SetLength(Words,Glyphs);
      for J:=0 to Glyphs-1 do
        Words[J]:=Copy(Bits,J*7+1,7);
      Physical:=EncodeT5M(Words);
      Name:=DecodeD7Text(Physical,Map,dsUkr);
      if (Name='') or (Pos(#10,Name)>0) or
         (Pos(#13,Name)>0) then
        raise Exception.Create('неприпустима укр-проєкція імені');
      Back:=EncodeD7Text(Name,Map,dsUkr);
      if Back<>Physical then
        raise Exception.Create('D7 укр round-trip змінив фізичні байти');
      Report:=Report+Name+#10;
    end;
    Result:=Report;
  finally
    Index.Free;
  end;
end;

var Report:RawByteString;
begin
  try
    if ParamCount<>1 then
      raise Exception.Create('використання: senscore1nazvy КОРІНЬ-РЕПОЗИТОРІЮ');
    Report:=BuildNames(ParamStr(1));
    Write(Report); { жодного часткового stdout після пізньої відмови }
  except
    on E:Exception do begin
      WriteLn(ErrOutput,'CORE1-НАЗВИ-ВІДМОВА: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
