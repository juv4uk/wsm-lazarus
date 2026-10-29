{ G6.119 — 39 різнополярних фізичних D12 кадрів для НСД.
  Фіксовані очікувані десяткові значення — ТІЛЬКИ тестові свідки;
  pinned SENS oracle незалежно обчислює кожний реальний результат.
  Фізичний .frame = 2 РІЗНІ ОКРЕМІ canonical packed .sens D12 атоми;
  .frame НЕ є одним двійковим документом SENS.
}
program test_elfd12nsdpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

procedure Pair(const Dir,LabelText,L,R,Expected:RawByteString);
var LeftAtom,RightAtom:RawByteString;
begin
  LeftAtom:=EncodeNumericDecimal(L,12);
  RightAtom:=EncodeNumericDecimal(R,12);
  if (Length(LeftAtom)<>3) or (Length(RightAtom)<>3) then
    raise Exception.Create('D12: expected three T5M bytes per atom');
  Save(Dir+'/'+String(LabelText)+'.frame',LeftAtom+RightAtom);
  Save(Dir+'/'+String(LabelText)+'-a.sens',LeftAtom);
  Save(Dir+'/'+String(LabelText)+'-b.sens',RightAtom);
  Save(Dir+'/'+String(LabelText)+'-expected.sens',
    EncodeNumericDecimal(Expected,12));
  WriteLn(LabelText,#9,L,#9,R,#9,Expected);
end;


var Dir:String;A,B,Frame:RawByteString;Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Pair(Dir,'01','12','18','6');
  Pair(Dir,'02','24','54','6');
  Pair(Dir,'03','13','17','1');
  Pair(Dir,'04','21','21','21');
  Pair(Dir,'05','2047','2046','1');
  Pair(Dir,'06','2047','2047','2047');
  Pair(Dir,'07','144','36','36');
  Pair(Dir,'08','987','610','1');
  Pair(Dir,'09','2046','1023','1023');
  Pair(Dir,'10','1024','256','256');
  Pair(Dir,'11','999','27','27');
  Pair(Dir,'12','157','31','1');
  Pair(Dir,'13','55','89','1');
  Pair(Dir,'14','1800','420','60');
  Pair(Dir,'15','1','2047','1');
  Pair(Dir,'16','2047','1','1');

  Pair(Dir,'17','0','1','1');
  Pair(Dir,'18','1','0','1');
  Pair(Dir,'19','0','0','0');
  Pair(Dir,'20','-1','3','1');
  Pair(Dir,'21','3','-1','-1');
  Pair(Dir,'22','-12','-18','-6');
  Pair(Dir,'23','-24','54','6');
  Pair(Dir,'24','24','-54','-6');
  Pair(Dir,'25','-2048','2047','1');
  Pair(Dir,'26','2047','-2048','-1');
  Pair(Dir,'27','-2048','1','1');
  Pair(Dir,'28','-2048','1024','1024');
  Pair(Dir,'29','-2048','-1024','-1024');
  Pair(Dir,'30','0','-2047','-2047');
  Pair(Dir,'31','-2047','0','-2047');
  Pair(Dir,'32','-2048','-2047','-1');
  Pair(Dir,'33','-2047','-2047','-2047');
  Pair(Dir,'34','-999','27','27');
  Pair(Dir,'35','0','-1','-1');
  Pair(Dir,'36','1','-2048','-1');

  Pair(Dir,'37','-2048','0','-2048');
  Pair(Dir,'38','0','-2048','-2048');
  Pair(Dir,'39','-2048','-2048','-2048');

  A:=EncodeNumericDecimal('1',12);
  B:=EncodeNumericDecimal('1',12);
  Frame:=A+B;
  Save(Dir+'/empty.frame','');
  Save(Dir+'/short1.frame',Copy(Frame,1,1));
  Save(Dir+'/short5.frame',Copy(Frame,1,5));
  Save(Dir+'/extra.frame',Frame+#0);
  Save(Dir+'/invalid243.frame',#$FF+Copy(Frame,2,5));
  Save(Dir+'/badfirst.frame',#$02+Copy(Frame,2,5));
  Save(Dir+'/badsecond.frame',Copy(Frame,1,3)+#$02+Copy(Frame,5,2));
  Save(Dir+'/badthird.frame',Copy(Frame,1,2)+#0+Copy(Frame,4,3));
  Save(Dir+'/badlast.frame',Copy(Frame,1,5)+#0);
  Save(Dir+'/newline.frame',Frame+#10);
  Save(Dir+'/projection.frame',
    RawByteString(UTF8Encode(UnicodeString('(найбільший-спільний-дільник 1 1)')))+#10);
  SetLength(Words,1);Words[0]:='1';
  Save(Dir+'/d1.frame',EncodeT5M(Words)+EncodeT5M(Words));
  WriteLn(ErrOutput,'D12-NSD-STDIN-FIXTURES-OK positives=39 rejects=12');
end.
