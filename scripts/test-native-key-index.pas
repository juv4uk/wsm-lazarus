{ G3.6: незалежний механічний доказ прискореного індексу borrowed вузлів.
  Вхідні координати походять з pinned SENS через TNativeEvaluator;
  тестовий масив є штучним фізичним механізмом, не мовним законом. }
program test_native_key_index;
{$mode objfpc}{$H+}
uses SysUtils, wsm.source, wsm.domain, wsm.nativeeval;

const LargeCount=32768;
var
  Engine:TNativeEvaluator;
  Nodes:array of TSourceNode;
  Keys, Oversized:TNativeKeyedAtoms;
  Foreign:TSourceNode;
  I, Checks:SizeInt;
  Got:RawByteString;

procedure Check(Condition:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,'ІНДЕКС-КЛЮЧІВ-ПРОВАЛ: ',Why);
    Halt(1);
  end;
end;

procedure ExpectReject(const Why:String; Node:TSourceNode;
  const Binding:TNativeKeyedAtoms);
var Rejected:Boolean; Value:RawByteString;
begin
  Rejected:=False;
  try
    Value:=Engine.EvaluateKeyedNode(Node,Binding);
    if Value='never' then Check(False,'неприпустимий результат');
  except
    on X:ENativeEvalError do begin
      Rejected:=True;
      Check((X.ByteOffset>=1) and (X.Line>=1) and
        (X.ByteColumn>=1),'позиція механічної помилки: '+Why);
    end;
    on X:EDomainError do Rejected:=True;
  end;
  Check(Rejected,'не відхилено: '+Why);
end;

begin
  Checks:=0;
  Engine:=TNativeEvaluator.Create('external/sens');
  Foreign:=nil;
  SetLength(Nodes,LargeCount);
  SetLength(Keys,LargeCount);
  try
    { Зворотний порядок записів і різні Node-адреси:
      не можна припускати монотонне виділення пам'яті алокатором. }
    for I:=0 to LargeCount-1 do begin
      Nodes[I]:=TSourceNode.Create;
      Nodes[I].Kind:=skAtom;
      Nodes[I].Text:=''; { це НЕ `ук` і не дозволений fallback }
      Nodes[I].ByteOffset:=I+1;
      Nodes[I].Line:=1;
      Nodes[I].ByteColumn:=1;
      Keys[LargeCount-1-I].Node:=Nodes[I];
      Keys[LargeCount-1-I].Key:=ExactKey('0');
    end;
    Keys[LargeCount-1].Key:=ExactKey('1');
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      'exact D1:1 після сортування великої таблиці');
    Check(Engine.EvaluateKeyedNode(Nodes[LargeCount-1],Keys)='0',
      'exact D1:0 з іншого краю таблиці');
    Check((Keys[0].Node=Nodes[LargeCount-1]) and
      (Keys[LargeCount-1].Node=Nodes[0]),
      'не змінено caller-owned масив');
    Check(Engine.EvaluateSource(#$D0#$BD#$D1#$96)='0',
      'окрема українська проєкція працює після фізичного режиму');

    { Ні дубльована адреса, ні nil не можуть вибрати випадковий key. }
    Keys[1].Node:=Keys[0].Node;
    ExpectReject('повторний вузол',Nodes[0],Keys);
    Keys[1].Node:=Nodes[LargeCount-2];
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      'відновлення після дублікатів');

    Keys[1].Node:=nil;
    ExpectReject('nil фізична адреса',Nodes[0],Keys);
    Keys[1].Node:=Nodes[LargeCount-2];
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      'відновлення після nil');

    Foreign:=TSourceNode.Create;
    Foreign.Kind:=skAtom;
    Foreign.Text:=''; Foreign.ByteOffset:=7;
    Foreign.Line:=1; Foreign.ByteColumn:=1;
    ExpectReject('відсутній borrowed вузол',Foreign,Keys);
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      'відновлення після невідомого вузла');

    { Неприпустима бітова ширина не підмінює D1. }
    Keys[100].Key.Width:=0;
    ExpectReject('неприпустима ширина',Nodes[0],Keys);
    Keys[100].Key:=ExactKey('0');
    Keys[100].Key.Bits:=2;
    ExpectReject('неприпустимі біти',Nodes[0],Keys);
    Keys[100].Key:=ExactKey('0');

    { D3:000 порожня структура НЕ є D1:0 як скалярне значення. }
    Keys[LargeCount-1].Key:=ExactKey('000');
    ExpectReject('D3:000 як D1 значення',Nodes[0],Keys);
    Keys[LargeCount-1].Key:=ExactKey('1');

    { Порожній D3-список не потребує жодного keyed atom. }
    Foreign.Kind:=skList;
    SetLength(Oversized,0);
    Check(Engine.EvaluateKeyedNode(Foreign,Oversized)='()',
      'порожнє D3 значення збережено');

    SetLength(Oversized,65537);
    ExpectReject('перевищено 65536 ключів',Nodes[0],Oversized);
    SetLength(Oversized,0);
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      'фінальне відновлення exact D1:1');
    Check(Engine.EvaluateSource(#$D1#$82#$D0#$B0#$D0#$BA)='1',
      'після помилок немає витоку keyed режиму в українську проєкцію');
    WriteLn('ІНДЕКС-КЛЮЧІВ-ГАРАЗД ключів=',LargeCount,
      ' пошук=логарифмічний сортування=купа ',
      'дублікат=відмова nil=відмова ширина=точна ',
      'вихід_після_помилки=відновлено перевірок=',Checks);
  finally
    Foreign.Free;
    for I:=0 to High(Nodes) do Nodes[I].Free;
    Engine.Free;
  end;
end.
