/-
# WorldCore — the Mathlib-free part of the model

Everything a runner needs, with no Mathlib in the import closure (enforced
by `check-core-imports.sh`). `World` imports all of this and adds the
Finset-based definitions and the theorems that need Mathlib.
-/
import World.Claim
import World.Log
import World.TxOrder
import World.Status
import World.Visible
import World.Traverse
import World.Ranked
import World.Admission
import World.ConflictsCore
import World.ClashCore
import World.Document
import World.Shapes
import World.CarryForward
