{ G6.156 — негативні фізичні свідки для СПІЛЬНОГО D5 WideIR→ELF.
  Потрібні лише pinned T5M байти, ніякого текстового dispatch. }
program test_irwidefront_mixed_d5;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m;
type ETestMix=class(Exception);
var Folder:String;Original,Physical:RawByteString;
    W,Mutated:TExactWords;I,Index:SizeInt;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ETestMix.Create(Why) end;

{ FileName — borrowed host шлях; Result — owned RawByteString з точними
  фізичними T5M байтами, FileStream належить цій функції.
  1) Чому .sens байти не слід читати як UTF-8?
  2) Хто звільняє потік?
  3) Чому не визначаємо D12 через довжину файла? }
function LoadFile(const Name:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Name,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=1) and (F.Size<8192),'помилкова довжина fixture');
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Output файли — ізольований тестовий каталог, не SENS джерело законів.
  Вміст є owned physical T5M, публікація в цьому тесті одноразова.
  1) Чому хибна голова D6 мусить зберегти свою ширину?
  2) Чому негативи не вважаються SENS програмами?
  3) Чому структурне D3:000 не може замінити D12? }
procedure Save(const Name:String;const Value:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Name,fmCreate);
  try if Length(Value)>0 then F.WriteBuffer(Value[1],Length(Value));
  finally F.Free end;
end;

begin
  try
    Need(ParamCount=1,'потрібен каталог фізичних свідків');
    Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
    Original:=LoadFile(Folder+'2-8.sens');
    DecodeT5M(Original,W);
    Need((Length(W)>8) and (W[0]='10') and (W[High(W)]='01') and
         (Length(W[1])=5),'спочатку потрібне правильне змішане дерево');
    Mutated:=Copy(W,0,Length(W));
    Mutated[1]:='10110';
    Save(Folder+'bad-root-mul.sens',EncodeT5M(Mutated));
    Index:=-1;
    for I:=2 to High(W) do
      if (W[I]='01010') or (W[I]='01011') then begin Index:=I;Break end;
    Need(Index>=0,'немає вкладеної D5 голови');
    Mutated:=Copy(W,0,Length(W));
    Mutated[Index]:='001110';
    Save(Folder+'bad-inner-d6.sens',EncodeT5M(Mutated));
    Index:=-1;
    for I:=2 to High(W) do
      if Length(W[I])=12 then begin Index:=I;Break end;
    Need(Index>=0,'немає фізичного D12 листка');
    Mutated:=Copy(W,0,Length(W));
    Mutated[Index]:=StringOfChar('0',23)+'1';
    Save(Folder+'bad-leaf-d24.sens',EncodeT5M(Mutated));
    Mutated:=Copy(W,0,Length(W));
    Mutated[High(Mutated)]:='11';
    Save(Folder+'bad-d2-close.sens',EncodeT5M(Mutated));
    SetLength(Mutated,Length(W)+1);
    for I:=0 to High(W) do Mutated[I]:=W[I];
    Mutated[High(Mutated)]:='1';
    Save(Folder+'bad-two-roots.sens',EncodeT5M(Mutated));
    Save(Folder+'bad-t5m.sens',#$FF);
    Save(Folder+'bad-empty.sens','');
    Save(Folder+'not-physical.lisp',Original);
    WriteLn('ЗМІШАНЕ-D5-НЕГАТИВИ-ГОТОВО cases=7 projection=1');
  except on E:Exception do begin
    WriteLn(StdErr,'ЗМІШАНЕ-D5-НЕГАТИВИ-ПРОВАЛ: ',E.Message);
    Halt(1)
  end end;
end.
