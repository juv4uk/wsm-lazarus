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
    WriteLn(StdErr,#$D0#$86#$D0#$9D#$D0#$94#$D0#$95#$D0#$9A#$D0#$A1#$2D#$D0#$9A#$D0#$9B#$D0#$AE#$D0#$A7#$D0#$86#$D0#$92#$2D#$D0#$9F#$D0#$A0#$D0#$9E#$D0#$92#$D0#$90#$D0#$9B#$3A#$20,Why);
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
    if Value='never' then Check(False,#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B8#$D0#$BF#$D1#$83#$D1#$81#$D1#$82#$D0#$B8#$D0#$BC#$D0#$B8#$D0#$B9#$20#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82);
  except
    on X:ENativeEvalError do begin
      Rejected:=True;
      Check((X.ByteOffset>=1) and (X.Line>=1) and
        (X.ByteColumn>=1),#$D0#$BF#$D0#$BE#$D0#$B7#$D0#$B8#$D1#$86#$D1#$96#$D1#$8F#$20#$D0#$BC#$D0#$B5#$D1#$85#$D0#$B0#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$BE#$D1#$97#$20#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BA#$D0#$B8#$3A#$20+Why);
    end;
    on X:EDomainError do Rejected:=True;
  end;
  Check(Rejected,#$D0#$BD#$D0#$B5#$20#$D0#$B2#$D1#$96#$D0#$B4#$D1#$85#$D0#$B8#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BE#$3A#$20+Why);
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
      #$65#$78#$61#$63#$74#$20#$44#$31#$3A#$31#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D1#$81#$D0#$BE#$D1#$80#$D1#$82#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$B2#$D0#$B5#$D0#$BB#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$97#$20#$D1#$82#$D0#$B0#$D0#$B1#$D0#$BB#$D0#$B8#$D1#$86#$D1#$96);
    Check(Engine.EvaluateKeyedNode(Nodes[LargeCount-1],Keys)='0',
      #$65#$78#$61#$63#$74#$20#$44#$31#$3A#$30#$20#$D0#$B7#$20#$D1#$96#$D0#$BD#$D1#$88#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$BA#$D1#$80#$D0#$B0#$D1#$8E#$20#$D1#$82#$D0#$B0#$D0#$B1#$D0#$BB#$D0#$B8#$D1#$86#$D1#$96);
    Check((Keys[0].Node=Nodes[LargeCount-1]) and
      (Keys[LargeCount-1].Node=Nodes[0]),
      #$D0#$BD#$D0#$B5#$20#$D0#$B7#$D0#$BC#$D1#$96#$D0#$BD#$D0#$B5#$D0#$BD#$D0#$BE#$20#$63#$61#$6C#$6C#$65#$72#$2D#$6F#$77#$6E#$65#$64#$20#$D0#$BC#$D0#$B0#$D1#$81#$D0#$B8#$D0#$B2);
    Check(Engine.EvaluateSource(#$D0#$BD#$D1#$96)='0',
      #$D0#$BE#$D0#$BA#$D1#$80#$D0#$B5#$D0#$BC#$D0#$B0#$20#$D1#$83#$D0#$BA#$D1#$80#$D0#$B0#$D1#$97#$D0#$BD#$D1#$81#$D1#$8C#$D0#$BA#$D0#$B0#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$8F#$20#$D0#$BF#$D1#$80#$D0#$B0#$D1#$86#$D1#$8E#$D1#$94#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D1#$80#$D0#$B5#$D0#$B6#$D0#$B8#$D0#$BC#$D1#$83);

    { Ні дубльована адреса, ні nil не можуть вибрати випадковий key. }
    Keys[1].Node:=Keys[0].Node;
    ExpectReject(#$D0#$BF#$D0#$BE#$D0#$B2#$D1#$82#$D0#$BE#$D1#$80#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB,Nodes[0],Keys);
    Keys[1].Node:=Nodes[LargeCount-2];
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      #$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$B4#$D1#$83#$D0#$B1#$D0#$BB#$D1#$96#$D0#$BA#$D0#$B0#$D1#$82#$D1#$96#$D0#$B2);

    Keys[1].Node:=nil;
    ExpectReject(#$6E#$69#$6C#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D0#$B0#$D0#$B4#$D1#$80#$D0#$B5#$D1#$81#$D0#$B0,Nodes[0],Keys);
    Keys[1].Node:=Nodes[LargeCount-2];
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      #$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$6E#$69#$6C);

    Foreign:=TSourceNode.Create;
    Foreign.Kind:=skAtom;
    Foreign.Text:=''; Foreign.ByteOffset:=7;
    Foreign.Line:=1; Foreign.ByteColumn:=1;
    ExpectReject(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$62#$6F#$72#$72#$6F#$77#$65#$64#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BE#$D0#$BB,Foreign,Keys);
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      #$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$BD#$D0#$B5#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$BE#$D0#$B3#$D0#$BE#$20#$D0#$B2#$D1#$83#$D0#$B7#$D0#$BB#$D0#$B0);

    { Неприпустима бітова ширина не підмінює D1. }
    Keys[100].Key.Width:=0;
    ExpectReject(#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B8#$D0#$BF#$D1#$83#$D1#$81#$D1#$82#$D0#$B8#$D0#$BC#$D0#$B0#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B0,Nodes[0],Keys);
    Keys[100].Key:=ExactKey('0');
    Keys[100].Key.Bits:=2;
    ExpectReject(#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B8#$D0#$BF#$D1#$83#$D1#$81#$D1#$82#$D0#$B8#$D0#$BC#$D1#$96#$20#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8,Nodes[0],Keys);
    Keys[100].Key:=ExactKey('0');

    { D3:000 порожня структура НЕ є D1:0 як скалярне значення. }
    Keys[LargeCount-1].Key:=ExactKey('000');
    ExpectReject(#$44#$33#$3A#$30#$30#$30#$20#$D1#$8F#$D0#$BA#$20#$44#$31#$20#$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F,Nodes[0],Keys);
    Keys[LargeCount-1].Key:=ExactKey('1');

    { Порожній D3-список не потребує жодного keyed atom. }
    Foreign.Kind:=skList;
    SetLength(Oversized,0);
    Check(Engine.EvaluateKeyedNode(Foreign,Oversized)='()',
      #$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$94#$20#$44#$33#$20#$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$D0#$B7#$D0#$B1#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B6#$D0#$B5#$D0#$BD#$D0#$BE);

    SetLength(Oversized,65537);
    ExpectReject(#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D0#$B8#$D1#$89#$D0#$B5#$D0#$BD#$D0#$BE#$20#$36#$35#$35#$33#$36#$20#$D0#$BA#$D0#$BB#$D1#$8E#$D1#$87#$D1#$96#$D0#$B2,Nodes[0],Oversized);
    SetLength(Oversized,0);
    Check(Engine.EvaluateKeyedNode(Nodes[0],Keys)='1',
      #$D1#$84#$D1#$96#$D0#$BD#$D0#$B0#$D0#$BB#$D1#$8C#$D0#$BD#$D0#$B5#$20#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F#$20#$65#$78#$61#$63#$74#$20#$44#$31#$3A#$31);
    Check(Engine.EvaluateSource(#$D1#$82#$D0#$B0#$D0#$BA)='1',
      #$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$20#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BE#$D0#$BA#$20#$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94#$20#$D0#$B2#$D0#$B8#$D1#$82#$D0#$BE#$D0#$BA#$D1#$83#$20#$6B#$65#$79#$65#$64#$20#$D1#$80#$D0#$B5#$D0#$B6#$D0#$B8#$D0#$BC#$D1#$83#$20#$D0#$B2#$20#$D1#$83#$D0#$BA#$D1#$80#$D0#$B0#$D1#$97#$D0#$BD#$D1#$81#$D1#$8C#$D0#$BA#$D1#$83#$20#$D0#$BF#$D1#$80#$D0#$BE#$D1#$94#$D0#$BA#$D1#$86#$D1#$96#$D1#$8E);
    WriteLn(#$D0#$86#$D0#$9D#$D0#$94#$D0#$95#$D0#$9A#$D0#$A1#$2D#$D0#$9A#$D0#$9B#$D0#$AE#$D0#$A7#$D0#$86#$D0#$92#$2D#$D0#$93#$D0#$90#$D0#$A0#$D0#$90#$D0#$97#$D0#$94#$20#$D0#$BA#$D0#$BB#$D1#$8E#$D1#$87#$D1#$96#$D0#$B2#$3D,LargeCount,
      #$20#$D0#$BF#$D0#$BE#$D1#$88#$D1#$83#$D0#$BA#$3D#$D0#$BB#$D0#$BE#$D0#$B3#$D0#$B0#$D1#$80#$D0#$B8#$D1#$84#$D0#$BC#$D1#$96#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$81#$D0#$BE#$D1#$80#$D1#$82#$D1#$83#$D0#$B2#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3D#$D0#$BA#$D1#$83#$D0#$BF#$D0#$B0#$20,
      #$D0#$B4#$D1#$83#$D0#$B1#$D0#$BB#$D1#$96#$D0#$BA#$D0#$B0#$D1#$82#$3D#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0#$20#$6E#$69#$6C#$3D#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B0#$3D#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$B0#$20,
      #$D0#$B2#$D0#$B8#$D1#$85#$D1#$96#$D0#$B4#$5F#$D0#$BF#$D1#$96#$D1#$81#$D0#$BB#$D1#$8F#$5F#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BA#$D0#$B8#$3D#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BD#$D0#$BE#$D0#$B2#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$BE#$D0#$BA#$3D,Checks);
  finally
    Foreign.Free;
    for I:=0 to High(Nodes) do Nodes[I].Free;
    Engine.Free;
  end;
end.
