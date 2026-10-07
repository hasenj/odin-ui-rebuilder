# Fixed-height virtual lists

`Virtual_List` builds a scroll viewport and visible rows, plus at most five
keyboard targets: focused row, its immediate neighbors, and first/last item.
Per-frame work scales with the viewport, not the collection size. The file
manager and demo17 font browser both use this API.

```odin
Item_ID :: distinct u64
view: ui.Virtual_List // One instance per list/window; destroy on teardown.

// When the model changes, outside the per-frame hot path:
ui.virtual_list_set_items(&view, item_ids[:])

// Inside the builder, the current rectangle becomes the viewport:
ui.open_virtual_list(&view, row_height = 30)
// Optional scrollbar here, before preparing the visible rows.
for i in ui.virtual_list_rows(&view) {
    visible := ui.open_virtual_row(&view, i)
    // This row is focusable by default. Read input/build controls here.
    if visible {
        ui.paint(color = ...)
        // Paint labels, thumbnails, etc.
    }
    ui.close_rect()
}
ui.close_virtual_list(&view)

// On application/model disposal:
ui.destroy_virtual_list(&view)
```

`virtual_list_set_items` copies unique integer keys, including distinct integer
types, and rebuilds an O(N) key-to-index lookup. Call only when membership/order
changes; keys must describe the same model used to draw the rows. Stable keys
preserve declared row identities through insertion/reordering. Changing a list's
parent identity deliberately starts a new interaction/scroll scope.

Pass `reveal = index` to `open_virtual_list` for programmatic scrolling (e.g.
type-to-select). It reveals without requesting focus; request focus while
building that row if desired. Tab/Shift-Tab use normal focus traversal and core's
scroll reveal. Manual scrolling does not snap back to the focused item.
`virtual_list_focused_index(&view)` resolves the focused row or descendant's key
against the current model, including immediately after a model change.

The list owns its `open_scroll` scope. `current_scroll()` and widget scrollbars
work inside it. `virtual_list_rows` prepares the range after any scrollbar/`scroll_to` adjustment.
Each returned row must be opened once in ascending order and
closed with `close_rect()`. Set `focusable = false` on `open_virtual_row` when
only its child controls should participate in Tab order. Continue **declaring
those controls even offscreen**; `visible` is for skipping optional paint work,
not omitting the focused descendant. Clips suppress offscreen rendering/hits.

## State lifetime

Only declared identities retain `ui.state`. Focused rows and their neighbors
remain declared offscreen, preserving a built editor's composition/state.
Other omitted rows lose UI state at frame end. Keep durable selection, edited
values and item data in the application model keyed by item ID. Drag state that
must survive omission also belongs there; this version does not pin arbitrary
active rows. Removing the focused key clears its focus instead of transferring
it to the replacement at that index. No O(N) retained UI tree is created.

Geometry is fixed-height and scroll offsets remain pixel-based across mutations.
Variable-height measurement, anchoring to the visible item when earlier rows
are inserted, and accessibility enumeration/reveal are future extensions.

The integration test uses 20,000 distinct keys and exercises offscreen focus,
Tab reveal, insertion/reversal, removal, empty/zero-height lists, retained state,
warm allocation reuse and full cleanup. File-manager captures additionally test
real watched-directory updates, type-to-select, and scroll jumps.
