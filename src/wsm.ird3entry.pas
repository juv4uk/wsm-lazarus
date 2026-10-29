{ G6.128 — єдиний фізичний вхід до ТРЬОХ УЖЕ ДОВЕДЕНИХ D3 ELF.
  Тут НЕ повторюються D3 закони, evaluator Core1 чи машинні emitters.
  Єдине джерело координат: pinned Contract12 → LoadPinnedDomains →
  BuildExactIR → VerifyExactIRStructure. Вибір вузького host профілю
  тільки з ключа (ширина,біти), завжди з повною повторною перевіркою
  у чинному спеціалізованому backend: simple EQ, nested EQ, COND.
  Kind — host діагностичний профіль, не SENS opcode і не реєстр законів.
  Physical — borrowed managed exact packed T5M. Tables/IR локальні
  managed буфери, Image — новий owned RawByteString після ELF guard.
  На будь-якій відмові Result='', Profile=dpNone; немає partial ELF.

  Запитання:
  1) Чому той самий D3:101 потребує двох окремих host профілів?
  2) Чому точні біти у paired D3/D7 не можна вгадувати за назвою?
  3) Чому backend повторно перевіряє ввесь source, а не довіряє роутеру?
  4) Що забезпечує provenance фізичних D2 вузлів у ExactIR?
  5) Чому структурний SIR1 не може виступати canonical .sens? }
unit wsm.ird3entry;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  EIRD3EntryError=class(Exception);
  TNativeD3Profile=(dpNone,dpSingleEq,dpNestedEq,dpCond);
function BuildVerifiedD3ELF(const Physical,AuthorityRoot:RawByteString;
  out Profile:TNativeD3Profile):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,wsm.exactirguard,
  wsm.ircallwriter,wsm.irnestedeqcall,wsm.ircondcall,
  wsm.elfgeometry;

procedure Need(OK:Boolean;const Reason:String);
begin
  if not OK then raise EIRD3EntryError.Create(Reason);
end;

function BuildVerifiedD3ELF(const Physical,AuthorityRoot:RawByteString;
  out Profile:TNativeD3Profile):RawByteString;
var
  Candidate:TNativeD3Profile;
  Tables:TDomainSet;
  IR:TExactIR;
  Stats:TExactIRGuardStats;
  Decoded:TExactWords;
  Image:RawByteString;
  Geometry:TELFGeometry;
begin
  Result:='';Profile:=dpNone;Candidate:=dpNone;Image:='';
  try
    Need((Length(Physical)>0) and (Length(Physical)<=65536),
      'D3-компілятор: розмір packed .sens виходить за межу');
    DecodeT5M(Physical,Decoded);
    Need(EncodeT5M(Decoded)=Physical,
      'D3-компілятор: неканонічні фізичні T5M байти');
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,IR);
    VerifyExactIRStructure(IR,Stats);
    Need((Length(IR.Roots)=1) and (Stats.Roots=1) and
      (IR.Roots[0]=0) and (Length(IR.Nodes)>=2) and
      (IR.Nodes[0].Kind=ikList) and
      (IR.Nodes[0].SubtreeEndExclusive=Length(IR.Nodes)) and
      (IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
      (IR.Nodes[1].RootIndex=0) and (IR.Nodes[1].ParentIndex=0) and
      (IR.Nodes[1].ChildIndex=0) and
      (IR.Nodes[1].SubtreeEndExclusive=2),
      'D3-компілятор: потрібна одна pinned D2 програма з точною головою');
    { Pinned keys, НЕ utf8 назви чи .lisp projection. D3=width 3. }
    Need(IR.Nodes[1].Key.Width=3,
      'D3-компілятор: невірний домен кореневої голови');
    if SameKey(IR.Nodes[1].Key,ExactKey('101')) then begin
      if Length(IR.Nodes)=4 then begin
        Candidate:=dpSingleEq;
        Image:=BuildPhysicalD3CallELF(Physical,AuthorityRoot);
      end else if Length(IR.Nodes)=10 then begin
        Candidate:=dpNestedEq;
        Image:=BuildPhysicalNestedEqCallELF(Physical,AuthorityRoot);
      end else
        raise EIRD3EntryError.Create(
          'D3-компілятор: для EQ допускаються лише 4 або 10 ExactIR вузлів');
    end else if SameKey(IR.Nodes[1].Key,ExactKey('110')) then begin
      Candidate:=dpCond;
      Image:=BuildIRCondCallELF(Physical,AuthorityRoot);
    end else
      raise EIRD3EntryError.Create(
        'D3-компілятор: pinned D3 закон не має перевіреного ELF профілю');
    VerifySENSELF64(Image,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=120) and
      (Geometry.FileBytes=Length(Image)) and
      (Geometry.MachineBytes>0) and (Geometry.MachineBytes<=256),
      'D3-компілятор: backend повернув непідтверджений PIE ELF64');
    Profile:=Candidate;
    Result:=Image;
  except
    on E:EIRD3EntryError do begin Result:='';Profile:=dpNone;raise end;
    on E:Exception do begin
      Result:='';Profile:=dpNone;
      raise EIRD3EntryError.Create(
        'D3-компілятор відхилив фізичне джерело: '+E.Message);
    end;
  end;
end;
end.
