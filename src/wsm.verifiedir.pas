{ G6.174. Перевірений контекст компіляції: одноразове декодування,
  одноразове завантаження pinned-доменів, одноразовий D2-розбір і bind.

  НАВІЩО. Виміряно читанням ланцюга (issue #47): після того як
  wsm.irwidefront.BuildVerifiedWideELF уже зробив DecodeT5M, EncodeT5M
  (канонічність), LoadPinnedDomains, BuildWideIR і VerifyWideIRStructure,
  бекенд wsm.elfquotet5m робить ТІ САМІ ТРИ ПРОХОДИ ВДРУГЕ:
    DecodeT5M         x2
    EncodeT5M         x2
    LoadPinnedDomains x2
  Цей модуль несе результат першого проходу далі, щоб другий не потрібен.

  ЧОГО ВІН НЕ РОБИТЬ:
    - не реалізує жодного мовного закону;
    - не створює другого реєстру доменів;
    - не замінює pinned juv4uk/sens;
    - не є кешем між програмами: контекст живе РІВНО ОДИН виклик.

  МЕЖІ ВОЛОДІННЯ. Усі поля — значення або власні об'єкти. Мутація
  зовнішніх змінних після Create не змінює вміст контексту. Після
  Free нічого не лишається: жодного статичного поля, жодного
  unit-level сховища.

  ПОРЯДОК СТВОРЕННЯ. Єдиний вхід — TVerifiedIR.Create. Він або
  повертає повністю перевірений контекст, або кидає виняток і не
  лишає часткового стану (try..except знищує все створене).
  Неперевірений IR передати неможливо: полів для запису ззовні немає. }
unit wsm.verifiedir;
{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, wsm.t5m, wsm.d2source, wsm.binarybind, wsm.bind;

type
  EVerifiedIRError = class(Exception);

  TVerifiedIR = class
  private
    FCanonicalT5M: RawByteString;
    FExact: TExactWords;
    FPinned: TDomainSet;
    FDocument: TD2Document;
    FBound: TBinaryWords;
    FHeadWidth: Byte;
    FHeadBits: RawByteString;
  public
    { ЄДИНИЙ вхід. Перевіряє все й повертає контекст або кидає.
      AuthorityRoot — корінь pinned juv4uk/sens, як і раніше. }
    constructor Create(const Physical, AuthorityRoot: RawByteString);
    destructor Destroy; override;

    { Точні байти, підтверджені як канонічні. Бекенд більше не
      перекодовує для цієї перевірки. }
    property CanonicalT5M: RawByteString read FCanonicalT5M;

    { Точна голова форми. Бекенд більше не перечитує D2 для неї. }
    property HeadWidth: Byte read FHeadWidth;
    property HeadBits: RawByteString read FHeadBits;

    { Готові результати проходів 1, 3, 4 — те, що бекенд будував удруге.
      Власність лишається за контекстом; назовні — лише читання. }
    property Exact: TExactWords read FExact;
    property Pinned: TDomainSet read FPinned;
    property Document: TD2Document read FDocument;
    property Bound: TBinaryWords read FBound;

    function IsValid: Boolean;
  end;

implementation
uses wsm.domain;

constructor TVerifiedIR.Create(const Physical, AuthorityRoot: RawByteString);
var
  RoundTrip: RawByteString;
  Head: TD2Node;
begin
  inherited Create;
  FCanonicalT5M := '';
  SetLength(FExact, 0);
  FillChar(FPinned, SizeOf(FPinned), 0);
  FDocument := nil;
  SetLength(FBound, 0);
  FHeadWidth := 0;
  FHeadBits := '';

  try
    { Host-межа ресурсу. Не мовний закон — захист від необмеженого входу. }
    if (Length(Physical) < 1) or (Length(Physical) > 65536) then
      raise EVerifiedIRError.Create('Фізичне джерело поза host-межею');

    { Крок 1: декодування. Один раз на весь виклик компіляції. }
    DecodeT5M(Physical, FExact);

    { Крок 2: канонічність. Перекодування ЛИШАЄТЬСЯ ОБОВ'ЯЗКОВИМ:
      саме воно відрізняє канонічний T5M від довільного набору байтів.
      Це перевірка безпеки, а не повторна робота. }
    RoundTrip := EncodeT5M(FExact);
    if RoundTrip <> Physical then
      raise EVerifiedIRError.Create('Неканонічний T5M');

    { Крок 3: pinned-домени. Один раз; бекенд бере готові з FPinned. }
    LoadPinnedDomains(AuthorityRoot, FPinned);

    { Крок 4: D2-розбір і bind. Один раз. }
    FDocument := ParseD2Words(FExact);
    if FDocument = nil then
      raise EVerifiedIRError.Create('D2-розбір не повернув документ');
    BindD2Binary(FDocument, FPinned, FBound);

    { Точна голова — щоб бекенд не перечитував її вдруге. }
    if (Length(FDocument.Roots) <> 1) or (FDocument.Roots[0] = nil) or
       (FDocument.Roots[0].Kind <> dkList) or
       (Length(FDocument.Roots[0].Children) < 1) then
      raise EVerifiedIRError.Create('Потрібна одна фізична форма');
    { VerifiedIR передає lowering ТІЛЬКИ фізичну координату голови.
      D3:000 (dkEmpty) — окрема порожня ідентичність, а вкладений
      список (dkList) — структура, НЕ виклична координата. Жодна
      текстова назва чи статус механізму тут не використовується.
      Відхиляємо ще до публікації повного контексту. }
    Head := FDocument.Roots[0].Children[0];
    if (Head = nil) or (Head.Kind <> dkIdentity) then
      raise EVerifiedIRError.Create('Голова форми не є точною координатою');
    if (Head.Width < 1) or (Head.Width <> Length(Head.Bits)) or
       (Length(FBound) < 1) then
      raise EVerifiedIRError.Create('Неповна фізична голова форми');
    if (FBound[0].RootIndex <> 0) or
       (FBound[0].WordIndex <> Head.WordIndex) or
       (FBound[0].IsEmpty) or
       (FBound[0].Key.Width <> Head.Width) or
       (KeyBits(FBound[0].Key) <> Head.Bits) then
      raise EVerifiedIRError.Create('Голова і pinned binder розходяться');
    FHeadWidth := Head.Width;
    FHeadBits := Head.Bits;

    FCanonicalT5M := Physical;
  except
    { Помилка знищує тимчасовий стан: жодного часткового контексту. }
    FreeAndNil(FDocument);
    SetLength(FExact, 0);
    SetLength(FBound, 0);
    FillChar(FPinned, SizeOf(FPinned), 0);
    raise;
  end;
end;

destructor TVerifiedIR.Destroy;
begin
  FreeAndNil(FDocument);
  SetLength(FExact, 0);
  SetLength(FBound, 0);
  FillChar(FPinned, SizeOf(FPinned), 0);
  FCanonicalT5M := '';
  FHeadBits := '';
  inherited Destroy;
end;

function TVerifiedIR.IsValid: Boolean;
begin
  Result := (FHeadWidth > 0) and (Length(FCanonicalT5M) > 0) and
            (FDocument <> nil);
end;

end.
