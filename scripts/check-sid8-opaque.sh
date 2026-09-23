#!/usr/bin/env bash
# check-sid8-opaque.sh — forbids mathematical/ordinal treatment of TSid8.
#
# Owner (2026-09-23): "треба заборонити математичні операції над нашим
# сідом" (mathematical operations on our SID must be forbidden).
#
# TSid8 (wsm.values.pas) already admits only two operators, = and <>
# (identity comparison) -- no +, -, *, div, mod, <, >, <=, >= exist, so
# ordinary arithmetic/ordering expressions on a TSid8 value already fail
# to compile. But FPC's ordinal typecast mechanism bypasses `strict
# private` entirely for same-SIZE conversions: empirically confirmed
# 2026-09-23, `Byte(someSid)` and `ShortInt(someSid)` (both exactly one
# byte, matching TSid8's own size) compile and extract the raw packed
# value as an ordinary number -- after which arbitrary arithmetic works
# freely. Every larger ordinal type (Integer/Word/Cardinal/QWord) is
# correctly rejected by FPC as an "Illegal type conversion"; only the
# two same-size types are the actual exploit surface.
#
# This is a source-pattern guard, not a language-level fix -- FPC has no
# way to forbid a same-size ordinal typecast at the type-declaration
# level itself. Fails closed on the literal cast syntax appearing
# anywhere in this codebase's own Pascal source.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -rnE '\b(Byte|ShortInt)\(' src/ scripts/ tests/ --include='*.pas' --include='*.lpr'; then
  echo 'SID8-OPAQUE-FAIL a same-size ordinal typecast (Byte(...)/ShortInt(...)) was found -- this bypasses TSid8'"'"'s strict-private encapsulation and admits arithmetic on a SID' >&2
  exit 1
fi

echo 'SID8-OPAQUE-OK no Byte(...)/ShortInt(...) typecast found anywhere -- TSid8 stays a non-arithmetic opaque identity'
