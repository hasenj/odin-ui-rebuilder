# Identity and animation

Every window owns an identity tree with a permanent root. Each update declares
the current tree again; matching nodes keep their handles and retained state.
This tree records logical scope and sibling order, independently of layout.

A node is identified by `(parent identity, key, occurrence among that key)`.
Occurrences start at zero for each key under each parent each frame. Inserting
or reordering other keys does not change a node's identity. Inserting an earlier
occurrence of the same key shifts the identities of later occurrences. Explicit
item keys are therefore useful for reorderable lists.

The implicit key is Odin's `#caller_location` (file, procedure, line and column).
It is stable during a running program, not intended as a persistent ID across
source edits/rebuilds. Explicit integer keys **replace** the location key:

```odin
Document_ID :: distinct u64

ui.open_identity(key = Document_ID(42))
{
    ui.open_rect(.Top, 80) // Location key scoped beneath document 42.
    {
        id := ui.current_identity()
        // ...
    }
    ui.close_rect()
}
ui.close_identity()
```

Integer keys retain their exact type as well as their value, including distinct
integer types and signed/unsigned integers up to 128 bits. `Document_ID(42)`,
`u64(42)` and `int(42)` are different keys. Strings, floats, pointers and enum keys
are not supported. A plain integer literal gets its default integer type.

`open_identity()` opens a logical scope without affecting rect geometry and
returns its `Identity`. `current_identity()` returns the current node's handle.
`open_rect` and `close_rect` also open and close identity nodes. Rect and identity
scopes must close in nesting order; closing the wrong kind is an assertion error.
`open_rect` accepts either `key = integer` or `loc = caller_location`.

Component wrappers should forward the location of their caller:

```odin
button :: proc(loc := #caller_location) {
    ui.open_rect(.Top, 80, loc = loc)
    {
        // ...
    }
    ui.close_rect()
}
```

The handle is an index plus a generation, valid only for its owning window.
`identity_valid(id)` checks it during an update. Nodes absent from a completed
frame are reclaimed, including their animation state. They remain valid until
that frame ends; a node reappearing after an absent frame receives a new handle.
Slots are reused with a new generation, retiring permanently on generation
exhaustion. There is no grace period or exit animation yet.

## Float animation

```odin
target: f32 = 0
if ui.hovered() { target = 1 }
amount := ui.animate_f32(target, half_life = 0.06)
color := normal + (hover_color - normal) * amount
ui.paint(color = color, corners = 12)
```

`animate_f32` opens and closes an identity child under the current node, using
its caller location or an explicit integer `key`. Thus separate animation calls
get separate state, and repeated calls with the same key follow the same
occurrence rule as other identity nodes. Animation nodes participate in sibling
ordering and key occurrence counts too.

On first appearance, the value initializes to the target. Subsequent calls move
the previous value toward the new target with exponential smoothing:

`value += (target - value) * (1 - 2^(-elapsed / half_life))`

The half-life is finite, positive, and expressed in seconds. Targets must be
finite. Elapsed time comes from the window's monotonic frame time; no start/end
times are required and reversal starts from the current value. Near the target,
the result snaps exactly to it (tolerance `1e-5 * max(1, abs(target))`). Repeated
calls in successive frames at the same time do not advance a stable target.
Color interpolation is the caller's choice; app8 interpolates RGB using one
retained hover amount per button. No automatic animation scheduling is needed
with the current continuously drawing window backends.

## Storage

Nodes live in a flat slot array, with generational parent/child/sibling links.
Current sibling links are rebuilt in declaration order each frame. Two shared
hash tables resolve full identity paths and count per-key occurrences; keys use
full equality, not only hashes. There is no separate map allocation per node.
Source locations borrow the compiler's static strings. Float animation records
live in a separate table keyed by node handles.

End-of-frame reclamation scans allocated node slots and removes unseen nodes
from all lookup/state tables. Slot/map capacities retain their high-water marks;
retained entries track live nodes rather than the history of all keys. Changing
all keys can temporarily require both the old and new nodes until reclamation.
Unchanged frames perform no Odin allocations once capacities are warm. All
storage is released with the window.
