{ G6.141 — фізичне INLINE двох ПРЯМО ПРОЧИТАНИХ Core1 визначень
  в ОДИН native ELF64. Визначення не дублюються в Pascal: джерело тільки
  external/sens/lib/core1.sens pinned Contract 12; D7 — точні гліфи,
  не назви для semantic dispatch. Два вже ратифіковані D5 тіла з
  позиційними параметрами спеціалізуються через існуючий compiler
  wsm.irarithchain, який видає машинні ADD і SUB та T5M stdout.

  RepoRoot, фізичні три аргументи позичені; Result — власні managed
  байти ELF або T5M. Doc і Runtime належать цій функції (try/finally).
  1) Чому фізична канонічна .sens не заміняється на укр .lisp?
  2) Чому D7 glyphs порівнюються з урахуванням семибітної ширини?
  3) Як перевіряється source provenance ОБОХ бібліотечних тіл?
  4) Чому другий результат D12 не можна отримати шляхом обрізання D24?
  5) Хто виконує ISA lowering, і чому це не загальний call ABI? }
unit wsm.lowercore1twocalls;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ELowerCore1TwoCallsError=class(Exception);
function BuildPinnedCore1TwoCallsELF(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
function PinnedCore1TwoCallsAnswer(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.numericplane,
     wsm.core1selektor,wsm.irarithchain,wsm.elfgeometry;

const MaxPinnedBytes=4*1024*1024;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ELowerCore1TwoCallsError.Create(Why);
end;

{ Raw binary file — own TFileStream, never Unicode text:
  neither host byte length nor Ukrainian projected names confer identity. }
function PinnedBytes(const Root:String):RawByteString;
var F:TFileStream;Path:String;
begin
  Need((Root<>'') and (Length(Root)<4096),'не вказано корінь pinned Core1');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(Root))+
    'external/sens/lib/core1.sens';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MaxPinnedBytes),
      'фізичний Core1 відсутній або виходить за квоту');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Для імені тільки D2-список з W7, НЕ текстове порівняння.
  Кожне фізичне W7 займає рівно сім бітів, керований Result — їх
  точна конкатенація лише всередині D7-ідентичності. }
function D7Name(const N:TD2Node):RawByteString;
var K:SizeInt;
begin
  Need((N<>nil) and (N.Kind=dkList) and
    (Length(N.Children)>0) and (Length(N.Children)<=256),
    'ім’я або параметр — не непорожній D7-список');
  Result:='';
  for K:=0 to High(N.Children) do begin
    Need((N.Children[K]<>nil) and
         (N.Children[K].Kind=dkIdentity) and
         (N.Children[K].Width=7) and
         (Length(N.Children[K].Bits)=7),
      'ім’я містить не W7-гліф');
    Result:=Result+N.Children[K].Bits;
  end;
end;

{ Знайти рівно ДВА source-backed DEFINE з одношаровими бінарними
  D5 тілами та двома ПОЗИЦІЙНИМИ D7-параметрами.
  01010/01011: координати із pinned D5, їхня семантика НЕ тут.
  Не приписуємо назви за текстом і не покладаємося на номер DEFINE;
  неоднозначність і змінений pinned census — fail closed. }
procedure ExtractPair(const RepoRoot:String;
  out AddName,SubName:RawByteString);
var Physical:RawByteString;W:TExactWords;D:TD2Document;
    Runtime:TCore1Selektor;Root,Lambda,Params,Body:TD2Node;
    K,CountAdd,CountSub,Ordinal:SizeInt;
    LeftKey,RightKey,Name,Head:RawByteString;
begin
  AddName:='';SubName:='';CountAdd:=0;CountSub:=0;
  Physical:=PinnedBytes(RepoRoot);
  DecodeT5M(Physical,W);
  Need(EncodeT5M(W)=Physical,'Core1 неканонічний T5M');
  D:=ParseD2WordsWide(W);
  try
    Need(Length(D.Roots)=129,'змінився точний census pinned Core1');
    for K:=0 to High(D.Roots) do begin
      Root:=D.Roots[K];
      if (Root=nil) or (Root.Kind<>dkList) or
         (Length(Root.Children)<>3) then Continue;
      if (Root.Children[0].Kind<>dkIdentity) or
         (Root.Children[0].Width<>4) or
         (Root.Children[0].Bits<>'0011') then Continue;
      Lambda:=Root.Children[2];
      if (Lambda=nil) or (Lambda.Kind<>dkList) or
         (Length(Lambda.Children)<>3) then Continue;
      if (Lambda.Children[0].Kind<>dkIdentity) or
         (Lambda.Children[0].Width<>4) or
         (Lambda.Children[0].Bits<>'0010') then Continue;
      Params:=Lambda.Children[1];Body:=Lambda.Children[2];
      if (Params=nil) or (Params.Kind<>dkList) or
         (Length(Params.Children)<>2) or
         (Body=nil) or (Body.Kind<>dkList) or
         (Length(Body.Children)<>3) or
         (Body.Children[0].Kind<>dkIdentity) or
         (Body.Children[0].Width<>5) then Continue;
      Head:=Body.Children[0].Bits;
      if (Head<>'01010') and (Head<>'01011') then Continue;
      LeftKey:=D7Name(Params.Children[0]);
      RightKey:=D7Name(Params.Children[1]);
      Need(LeftKey<>RightKey,'параметри фізичного Core1 збігаються');
      Need((D7Name(Body.Children[1])=LeftKey) and
           (D7Name(Body.Children[2])=RightKey),
        'оригінальне Core1 тіло не відповідає порядку параметрів');
      Need((Body.WordIndex>=1) and
           (Body.EndWordIndexExclusive>Body.WordIndex) and
           (Body.EndWordIndexExclusive<=Length(W)+1) and
           (W[Body.WordIndex-1]='10') and
           (W[Body.EndWordIndexExclusive-2]='01'),
        'пошкоджені фізичні межі оригінального тіла');
      Name:=D7Name(Root.Children[1]);
      if Head='01010' then begin
        Inc(CountAdd);Need(CountAdd=1,'неоднозначне Core1 додавання');
        AddName:=Name;
      end else begin
        Inc(CountSub);Need(CountSub=1,'неоднозначне Core1 віднімання');
        SubName:=Name;
      end;
    end;
    Need((CountAdd=1) and (CountSub=1) and (AddName<>SubName),
      'не знайдені два різні оригінальні pinned Core1 DEFINE');
  finally D.Free end;
  Runtime:=TCore1Selektor.Create(RepoRoot);
  try
    Ordinal:=Runtime.FindAdmitted(AddName);
    Need((Ordinal>=0) and (Runtime.AdmittedParamCount(Ordinal)=2),
      'оригінальна функція додавання не допускається Core1');
    Ordinal:=Runtime.FindAdmitted(SubName);
    Need((Ordinal>=0) and (Runtime.AdmittedParamCount(Ordinal)=2),
      'оригінальна функція віднімання не допускається Core1');
  finally Runtime.Free end;
end;

{ Фізичний числовий атом: 12 exact бітів після повного codec
  round-trip і існуючого числового admission; жодної D24 підміни. }
function D12Bits(const Bytes:RawByteString):RawByteString;
var Words:TExactWords;N:TExplicitNumeric;
begin
  Need(Length(Bytes)>0,'порожній D12-аргумент');
  DecodeT5M(Bytes,Words);
  Need((Length(Words)=1) and (Length(Words[0])=12) and
       (EncodeT5M(Words)=Bytes),'не один канонічний фізичний D12');
  N:=ReadNumericPhysical(Bytes,12);
  Need((N.DomainWidth=12) and (N.ExactBits=Words[0]),
    'порушено точну двійкову ідентичність D12');
  Result:=Words[0];
end;

{ Побудова лише СПЕЦІАЛІЗОВАНОГО IR з двох pinned D5 тіл.
  Спільний BuildIRArithChainELF ЗНОВУ перевірить D5 викличність,
  кожен D12 проміжний результат, дві машинні інструкції та T5M.
  Без backend duplication і без прихованого static host результату. }
function BuildPinnedCore1TwoCallsELF(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
var AddName,SubName,A,B,C,ProgramPhysical:RawByteString;
    Words:TExactWords;G:TELFGeometry;Authority:RawByteString;
begin
  Result:='';
  A:=D12Bits(APhysical);B:=D12Bits(BPhysical);C:=D12Bits(CPhysical);
  ExtractPair(RepoRoot,AddName,SubName);
  SetLength(Words,9);
  Words[0]:='10'; Words[1]:='01011';
  Words[2]:='10'; Words[3]:='01010';
  Words[4]:=A; Words[5]:=B; Words[6]:='01';
  Words[7]:=C; Words[8]:='01';
  ProgramPhysical:=EncodeT5M(Words);
  Authority:=RawByteString(
    IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+'external/sens');
  Result:=BuildIRArithChainELF(ProgramPhysical,Authority);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Result)),
    'не вдалося перевірити реальний compiled ELF64 PIE');
end;

{ Для oracle/runtime: два РІЗНІ source-backed D7 DEFINE реально
  викликаються тим самим чинним TCore1Selektor, а не готовою відповіддю.
  Перша відповідь повинна бути D12, інакше backend справедливо відмовить.
  Зовнішня функція не є семантикою — тільки фізична побудова виклику. }
function Call2(const Name,L,R:RawByteString):RawByteString;
var W:TExactWords;N,K:SizeInt;
begin
  Need((Name<>'') and (Length(Name) mod 7=0),
    'неприпустимий точний D7 ключ виклику');
  N:=Length(Name) div 7;
  SetLength(W,N+6);
  W[0]:='10';W[1]:='10';
  for K:=0 to N-1 do W[K+2]:=Copy(Name,K*7+1,7);
  W[N+2]:='01';W[N+3]:=L;W[N+4]:=R;W[N+5]:='01';
  Result:=EncodeT5M(W);
end;

function PinnedCore1TwoCallsAnswer(const RepoRoot:String;
  const APhysical,BPhysical,CPhysical:RawByteString):RawByteString;
var AddName,SubName,A,B,C,Intermediate:RawByteString;
    Runtime:TCore1Selektor;W:TExactWords;
begin
  A:=D12Bits(APhysical);B:=D12Bits(BPhysical);C:=D12Bits(CPhysical);
  ExtractPair(RepoRoot,AddName,SubName);
  Runtime:=TCore1Selektor.Create(RepoRoot);
  try
    Intermediate:=Runtime.ExecutePhysicalCall(Call2(AddName,A,B));
    DecodeT5M(Intermediate,W);
    Need((Length(W)=1) and (Length(W[0])=12) and
         (EncodeT5M(W)=Intermediate),
      'перший реальний Core1 виклик вийшов за D12');
    Result:=Runtime.ExecutePhysicalCall(Call2(SubName,W[0],C));
  finally Runtime.Free end;
end;
end.
