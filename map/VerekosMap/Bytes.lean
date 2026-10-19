/-
# VerekosMap.Bytes — SHA-256, hex, and the slice-1 identifiers

SHA-256 is minidregg's `Compiler.Sha256` (FIPS 180-4, with known-answer
vectors in `Compiler.Sha256Vectors`); this file only turns its words into
bytes and hex.

`num` is mapper.py's identifier: SHA-256 over `VEREKOS/ID/v1 ∖0` and the
NUL-joined parts, the first 15 bytes as a big-endian integer, in decimal (`1`
if that is zero). This is slice 1's approximation 1 (W17 memo): minidregg
derives ids with `deriveIdentifier` over an `IdPreimage`, which the deployed
client does not expose. Reproduced exactly, for byte identity.
-/
import Compiler.Sha256

namespace VerekosMap

/-- The 32 digest bytes. -/
def sha256 (msg : ByteArray) : ByteArray := Id.run do
  let mut out := ByteArray.empty
  for w in Minidregg.Compiler.Sha256.digest msg do
    for i in [0:4] do
      out := out.push (UInt8.ofNat ((w.toNat >>> (8 * (3 - i))) % 256))
  return out

/-- Lowercase hex of bytes. -/
def hexBytes (b : ByteArray) : String := Id.run do
  let h := "0123456789abcdef".toList
  let mut out := ""
  for x in b do
    out := (out.push h[x.toNat / 16]!).push h[x.toNat % 16]!
  return out

/-- `hashlib.sha256(s.encode()).hexdigest()`. -/
def sha256Hex (s : String) : String := Minidregg.Compiler.Sha256.hexString s

/-- `mapper.py hexs`: the UTF-8 bytes of a text, in lowercase hex. -/
def hexs (s : String) : String := hexBytes s.toUTF8

def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- `bytes.fromhex(h)` (no whitespace accepted). -/
def unhex (h : String) : Except String ByteArray := do
  let cs := h.toList.toArray
  if cs.size % 2 != 0 then throw s!"odd-length hex ({cs.size})"
  let mut out := ByteArray.empty
  for i in [0:cs.size / 2] do
    match hexVal cs[2 * i]!, hexVal cs[2 * i + 1]! with
    | some a, some b => out := out.push (UInt8.ofNat (16 * a + b))
    | _, _ => throw "not hex"
  return out

/-- `bytes.fromhex(h).decode()` (UTF-8). -/
def unhexText (h : String) : Except String String := do
  match String.fromUTF8? (← unhex h) with
  | some s => pure s
  | none => throw "payload is not UTF-8"

/-- mapper.py `num(*parts)`: a 120-bit identifier as a decimal string. -/
def num (parts : List String) : String :=
  let pre := "VEREKOS/ID/v1".toUTF8.push 0 ++ ("\x00".intercalate parts).toUTF8
  let h := sha256 pre
  let n := (List.range 15).foldl (fun acc i => acc * 256 + (h.get! i).toNat) 0
  toString (if n == 0 then 1 else n)

/-- mapper.py `schema(name)`. -/
def schemaId (name : String) : String := num ["schema", name]

end VerekosMap
