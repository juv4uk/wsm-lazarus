{ Нативна візуальна демонстрація фізичного GC, не SENS-evaluator. }
program gc_inspector;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, SysUtils, wsm.gctimeline, wsm.gc;

var Viewer:TGCViewerForm; Data,Invalid:TGCMeasures;
procedure Require(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('GC-графіка: '+Why);
end;

procedure BuildPhysicalHistory;
var Heap:TGCHeap; Root:TGCFrameToken; A,B,C:TGCHandle; Freed:SizeInt;
begin
  SetLength(Data,4);
  Heap:=TGCHeap.Create;
  try
    Root:=Heap.BeginRootScope;
    A:=Heap.Allocate(11);
    Heap.RootInScope(Root,A);
    B:=Heap.Allocate(22);
    Heap.Link(A,B);
    Heap.Link(B,A);
    Data[0]:=CaptureGC(Heap,1,0);
    Freed:=Heap.Collect;
    Require(Freed=0,'досяжний цикл не можна збирати');
    Data[1]:=CaptureGC(Heap,2,Freed);
    Heap.EndRootScope(Root);
    Freed:=Heap.Collect;
    Require(Freed=2,'недосяжний цикл повинен звільнити два слоти');
    Data[2]:=CaptureGC(Heap,3,Freed);
    Require(not Heap.IsAlive(A),'застарілий фізичний handle активний');
    C:=Heap.Allocate(33);
    Require(Heap.IsAlive(C),'повторний слот неактивний');
    Require(not Heap.IsAlive(A),'старий handle воскрес після повторного використання');
    Data[3]:=CaptureGC(Heap,4,0);
  finally Heap.Free; end;
end;

procedure TestInvalid;
var Proof:RawByteString; Refused:Boolean;
  procedure Reject(const Description:String);
  begin
    Refused:=False;
    try Viewer.LoadHistory(Invalid);
    except on E:EGCTimelineError do Refused:=True; end;
    Require(Refused,'не відхилено '+Description);
    Require(Viewer.Evidence=Proof,'пошкоджено попередні дані: '+Description);
    Require(Viewer.SampleCount=4,'пошкоджено число рядків: '+Description);
  end;
begin
  Proof:=Viewer.Evidence;
  Invalid:=Copy(Data,0,Length(Data));
  Invalid[2].FreeSlots:=1;
  Reject('невідповідність live+free');
  Invalid:=Copy(Data,0,Length(Data));
  Invalid[2].Phase:=2;
  Reject('повторна фаза');
  Invalid:=Copy(Data,0,Length(Data));
  Invalid[0].Live:=-1;
  Reject('від’ємне число живих');
  Invalid:=Copy(Data,0,Length(Data));
  Invalid[1].Reclaimed:=3;
  Reject('звільнено більше ніж слотів');
  SetLength(Invalid,0);
  Reject('порожня історія');
  SetLength(Invalid,MaxGCSamples+1);
  Reject('понад 4096 знімків');
  Refused:=False;
  try CaptureGC(nil,1,0);
  except on E:EGCTimelineError do Refused:=True; end;
  Require(Refused,'nil heap дозволено');
  Refused:=False;
  try Viewer.Cell(0,0);
  except on E:EGCTimelineError do Refused:=True; end;
  Require(Refused,'невірну координату таблиці дозволено');
end;

procedure SelfTest;
var Proof:RawByteString;
begin
  Require(Viewer.SampleCount=4,'чотири фізичні фази');
  Require(Viewer.Cell(1,1)='2','початкова ємність');
  Require(Viewer.Cell(2,1)='2','два живі слоти');
  Require(Viewer.Cell(5,1)='1','один фізичний тимчасовий корінь');
  Require(Viewer.Cell(6,1)='1','одна фізична область коренів');
  Require(Viewer.Cell(2,3)='0','всі вузли зібрано');
  Require(Viewer.Cell(3,3)='2','два вільних слоти');
  Require(Viewer.Cell(7,3)='2','точне число звільнених');
  Require(Viewer.Cell(1,4)='2','повторне використання без росту');
  Require(Viewer.Cell(2,4)='1','один новий живий слот');
  Proof:=Viewer.Evidence;
  Require(Pos('3'#9'2'#9'0'#9'2'#9'0'#9'0'#9'0'#9'2'#10,Proof)>0,
    'UTF-8 TSV фізичний доказ фази звільнення');
  TestInvalid;
  Require(Viewer.Evidence=Proof,'незалежність знімка від GC');
  Viewer.Show;
  Viewer.Repaint;
  Application.ProcessMessages;
  Require(Viewer.PaintCount>0,'справжній LCL графік не малювався');
  WriteLn('LCL-GC-ГАРАЗД GTK2=так графік=намальовано фази=4 ',
    'rooted-cycle=живий reclaimed=2 slots=перевикористано ',
    'негативні=відхилено snapshot=незалежний семантика-SENS=не-стверджується');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — історія фізичної пам’яті';
    Application.CreateForm(TGCViewerForm,Viewer);
    BuildPhysicalHistory;
    Viewer.LoadHistory(Data);
    if (ParamCount=1) and (ParamStr(1)='--самоперевірка') then
      SelfTest
    else if ParamCount=0 then
      Application.Run
    else
      raise Exception.Create('використання: gc-inspector [--самоперевірка]');
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-GC-ПОМИЛКА: ',E.Message);
    Halt(2);
  end; end;
end.
