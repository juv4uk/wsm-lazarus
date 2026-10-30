{ G6: перевірка геометричного зростання фізичного WideIR.
  Жодного SENS закону: тільки bounded масиви, точний порядок,
  фізичні адреси, провал та відновлення. }
program test_wideir_rost;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
     wsm.domain, wsm.bind, wsm.wideir;
var Tables:TDomainSet; R:TWideIR; Checks:SizeInt;

procedure Demand(Okay:Boolean; const Reason:String);
begin
  if not Okay then begin
    WriteLn(StdErr,'ШИРОКЕ-ЗРОСТАННЯ-ВІДМОВА: ',Reason);
    Halt(1);
  end;
  Inc(Checks);
end;

{ Owned TExactWords і packed T5M; R має FPC-managed Nodes.
  Усі листки — дійсні точні D1:1, не host-числа.
  1) Чому скобки зберігають D2, а не задають закон D1?
  2) Чому I+1 є 1-based адресою слова?
  3) Чому RootIndex і ChildIndex не повинні змінюватися?
  4) Хто звільняє керовані масиви після перевірки? }
procedure CheckFlat(Atoms:SizeInt);
var Words:TExactWords; Physical:RawByteString; I:SizeInt;
begin
  SetLength(Words,Atoms+2);
  Words[0]:='10';
  for I:=1 to Atoms do Words[I]:='1';
  Words[Atoms+1]:='01';
  Physical:=EncodeT5M(Words);
  BuildWideIR(Physical,Tables,R);
  Demand((Length(R.Roots)=1) and (R.Roots[0]=0) and
    (Length(R.Nodes)=Atoms+1),'число коренів/вузлів');
  Demand((R.Nodes[0].Kind=wkList) and
    (R.PhysicalLeaves=Atoms) and (R.OpaqueLeaves=0),
    'точні фізичні листки');
  for I:=1 to Atoms do begin
    Demand((R.Nodes[I].Kind=wkAtom) and (R.Nodes[I].Width=1) and
      (R.Nodes[I].Bits='1') and R.Nodes[I].HasPinnedKey,
      'пошкодження D1 координати');
    Demand((R.Nodes[I].WordIndex=I+1) and
      (R.Nodes[I].ParentIndex=0) and
      (R.Nodes[I].RootIndex=0) and
      (R.Nodes[I].ChildIndex=I-1) and
      (R.Nodes[I].Depth=1),'пошкодження D2 порядку');
    Demand((R.Nodes[I].Physical.TritEnd-
      R.Nodes[I].Physical.TritStart=1) and
      (R.Nodes[I].Physical.ByteStart>=0),
      'пошкодження фізичної адреси');
    if I>1 then
      Demand(R.Nodes[I].Physical.TritStart>
        R.Nodes[I-1].Physical.TritEnd,
        'втрата фізичного роздільника');
  end;
  Demand(EncodeT5M(Words)=Physical,'байтовий T5M round-trip');
end;

{ Результат у випадку помилки має бути повністю порожнім.
  1) Чому 8193-й вузол не можна мовчки усікти?
  2) Чому за відмовою мусить іти успішне відновлення?
  3) Чому не можна трактувати malformed T5M як .lisp? }
procedure CheckReject(Atoms:SizeInt; BadByte:Boolean);
var Words:TExactWords; Physical:RawByteString; I:SizeInt; Rejected:Boolean;
begin
  if BadByte then Physical:=#243
  else begin
    SetLength(Words,Atoms+2);
    Words[0]:='10';
    for I:=1 to Atoms do Words[I]:='1';
    Words[Atoms+1]:='01';
    Physical:=EncodeT5M(Words);
  end;
  SetLength(R.Nodes,1);
  SetLength(R.Roots,1);
  R.PhysicalLeaves:=7; R.OpaqueLeaves:=7;
  Rejected:=False;
  try BuildWideIR(Physical,Tables,R);
  except on E:Exception do Rejected:=True; end;
  Demand(Rejected,'завелика або некоректна форма допущена');
  Demand((Length(R.Nodes)=0) and (Length(R.Roots)=0) and
    (R.PhysicalLeaves=0) and (R.OpaqueLeaves=0),
    'після відмови лишився частковий IR');
end;

begin
  Checks:=0;
  LoadPinnedDomains('external/sens',Tables);
  CheckFlat(31);
  CheckFlat(32);
  CheckFlat(33);
  CheckFlat(4095);
  CheckReject(MaxWideIRNodes,False);
  CheckReject(0,True);
  CheckFlat(33);
  WriteLn('ШИРОКЕ-IR-ЗРОСТАННЯ-ГАРАЗД: checks=',Checks,
    ' межа=',MaxWideIRNodes,' D7=НЕ-ЗМІНЕНО D12+=opaque');
end.
