{ G6.135 — оптимізація ВИКЛЮЧНО host машинного коду, без SENS
  закону, без нового reader, Core1 чи D7 name-dispatch.
  Спочатку чинний pinned BuildPhysicalNestedEqCallELF робить
  ВСЕ допущення canonical .sens/T5M + ExactIR і будує реальний ELF.
  Цей post-pass перевіряє конкретну відому топологію: три E8 rel32
  з ціллю у спільній 9-байтовій функції наприкінці машинного тіла.
  Замінюємо кожний 5-байтовий CALL на точне 8-байтове тіло тієї
  САМОЇ функції без RET, а 9-байтовий хвіст прибираємо:
  3 * (8-5) - 9 = 0 байтів. Жодної host D3 семантичної оцінки.
  CMP EDI,ESI/SETE AL/MOVZX EAX,AL виконує CPU 3 рази.
  Інших RIP-relative машинних fixup у допущеній старій формі немає.
  Original/Image — managed owned ELF bytes; Physical borrowed packed
  T5M; на відмові Result пустий, неторканий input і no publication.

  Питання: 1) чому без перевірки CALL target така заміна небезпечна?
  2) чому інлайн не змінює результат D1 і RSP на виході?
  3) чому розмір залишився точно такий самий?
  4) чому ця механічна оптимізація ще не доказ меншої енергії?
  5) хто засвідчує закон D3:101 і фізичне походження аргументів? }
unit wsm.irnestedinline;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRNestedInlineError=class(Exception);
function BuildPhysicalNestedEqInlineELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irnestedeqcall,wsm.elfgeometry;

const
  HeaderBytes=120;
  { Exact host callee from already merged shared-CALL machine writer. }
  SharedCallee=#$39#$F7#$0F#$94#$C0#$0F#$B6#$C0#$C3;
  CalleeSize=9;
  CallSize=5;
  InlineSize=8;
  ExpectedCalls=3;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRNestedInlineError.Create(Why);
end;

function CountByte(const Data:RawByteString;B:AnsiChar):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=1 to Length(Data) do
    if Data[I]=B then Inc(Result);
end;

{ 1-based machine CALL opcode position; rel32 little endian signed.
  Return: 0-based machine target. Не SENS слово та не Dn ключ.
  Питання: 1) звідки +5 у відліку? 2) чому signed32?
  3) що станеться, якщо target усередині іншої інструкції? }
function CallTarget(const Code:RawByteString;At:SizeInt):Int64;
var U:QWord;I:SizeInt;Delta:Int64;
begin
  Need((At>=1) and (At<=Length(Code)-4) and (Code[At]=#$E8),
    'Оптимізатор: невірний CALL rel32');
  U:=0;
  for I:=0 to 3 do
    U:=U or (QWord(Byte(Code[At+1+I])) shl (8*I));
  if U>=$80000000 then Delta:=Int64(U)-4294967296
  else Delta:=Int64(U);
  Result:=Int64(At-1)+CallSize+Delta;
end;

function RewriteMachine(const Machine:RawByteString):RawByteString;
var
  P,BodyLast,Calls:SizeInt;
  Target:Int64;
  Inlined:RawByteString;
begin
  Result:='';
  Need((Length(Machine)>CalleeSize+3*CallSize) and
       (Length(Machine)<=256),
    'Оптимізатор: непідтриманий розмір verified machine body');
  Need(Copy(Machine,Length(Machine)-CalleeSize+1,CalleeSize)=SharedCallee,
    'Оптимізатор: shared callee не збігається з перевіреним host тілом');
  Need((CountByte(Machine,#$E8)=ExpectedCalls) and
       (CountByte(Machine,#$C3)=1),
    'Оптимізатор: потрібно рівно три CALL і один RET');
  BodyLast:=Length(Machine)-CalleeSize;
  Inlined:=Copy(SharedCallee,1,InlineSize);
  P:=1;Calls:=0;
  while P<=BodyLast do begin
    if Machine[P]=#$E8 then begin
      Need(P+CallSize-1<=BodyLast,
        'Оптимізатор: обрізаний CALL перед shared callee');
      Target:=CallTarget(Machine,P);
      Need(Target=BodyLast,
        'Оптимізатор: CALL спрямовано не у єдину хвостову функцію');
      Result:=Result+Inlined;
      Inc(Calls);
      Inc(P,CallSize);
    end else begin
      Result:=Result+Machine[P];
      Inc(P);
    end;
  end;
  Need((Calls=ExpectedCalls) and
       (Length(Result)=Length(Machine)) and
       (CountByte(Result,#$E8)=0) and
       (CountByte(Result,#$C3)=0),
    'Оптимізатор: не всі CALL/RET усунуті без зміни довжини');
  Need(CountByte(Result,#$94)=ExpectedCalls,
    'Оптимізатор: три машинні SETE не збережені');
end;

function BuildPhysicalNestedEqInlineELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Original,Machine,NewMachine,Image:RawByteString;
  OriginalGeometry,NewGeometry:TELFGeometry;
begin
  Result:='';
  try
    Original:=BuildPhysicalNestedEqCallELF(Physical,AuthorityRoot);
    VerifySENSELF64(Original,OriginalGeometry);
    Need((OriginalGeometry.Kind=3) and (OriginalGeometry.Entry=HeaderBytes) and
      (OriginalGeometry.MachineBytes>0) and
      (OriginalGeometry.MachineBytes<=256),
      'Оптимізатор: потрібен pinned verified PIE ELF64 nested D3');
    Machine:=Copy(Original,HeaderBytes+1,OriginalGeometry.MachineBytes);
    NewMachine:=RewriteMachine(Machine);
    Image:=Copy(Original,1,HeaderBytes)+NewMachine;
    Need((Length(Image)=Length(Original)) and (Image<>Original),
      'Оптимізатор: ELF не змінено або змінено довжину');
    VerifySENSELF64(Image,NewGeometry);
    Need((NewGeometry.Kind=OriginalGeometry.Kind) and
      (NewGeometry.Entry=OriginalGeometry.Entry) and
      (NewGeometry.FileBytes=OriginalGeometry.FileBytes) and
      (NewGeometry.MachineBytes=OriginalGeometry.MachineBytes),
      'Оптимізатор: змінена або невірна геометрія PIE');
    Result:=Image;
  except
    on E:EIRNestedInlineError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRNestedInlineError.Create('Фізичне інлайн-розгортання D3 відхилено: '+E.Message);
    end;
  end;
end;
end.
