# Description

## Summary

On Linux (GTK), deleting an object that has several parts leaves the object list's `GtkTreeView` out of sync with `ObjectDataViewModel`. Later list changes can then make GTK abort the app. The most common trigger is **Assemble** on objects that are themselves assemblies; deleting such objects with the Delete key also triggers it. The cause is that `ObjectDataViewModel::Delete()` notifies the control about each part of an object, but wxGTK has never built those rows. This PR removes the object's row with a single notification on GTK.

One file is changed: `src/slic3r/GUI/ObjectDataViewModel.cpp` (+10 lines, all under `#ifdef __WXGTK__`). Windows and macOS are unchanged.

## Symptom

1. Open a project and import several `.3mf` files whose objects have several parts (each import adds "Assembly" objects).
2. Select two of those objects and use **Assemble** from the context menu, or delete them with the Delete key.
3. Every time, stderr shows:

   ```
   gtk_tree_path_append_index: assertion 'index_ >= 0' failed
   ```

   Sometimes, usually at the next Assemble, the app aborts with:

   ```
   Gtk:ERROR:../gtk/gtkrbtree.c:471:_gtk_rbtree_insert_after: assertion failed: (_gtk_rbtree_is_nil (tree->root))
   ```

   and `systemd-coredump` records a `SIGABRT` for `/app/CrealityPrint`.

## Root cause

1. **The control never builds an object's children.** The object list is drawn with ImGui, but `ObjectList` is still a `wxDataViewCtrl`, so a `GtkTreeView` sits behind it, fed by `ObjectDataViewModel`. wxGTK builds a node's children lazily, when GTK asks for them. Since that tree view is never expanded or shown to the user, the parts of an object are never built on the wxGTK side.

2. **Deleting an object notified each part.** In `ObjectDataViewModel::Delete()`, the `itObject` branch first deleted every child with a recursive `Delete()`, and each one sent `ItemDeleted(object, child)`.

3. **wxGTK turns an unknown child into the wrong row.** `wxGtkDataViewModelNotifier::ItemDeleted()` builds the GTK path from the parent's path plus `GetIndexOf(parent_node, item)`. For a child it never built, `GetIndexOf()` returns `-1`. `gtk_tree_path_append_index()` rejects `-1` (the assertion above), so the path stays the **object's own path**, and `gtk_tree_model_row_deleted()` deletes the object's row (or whichever row is at that path) instead of the child.

4. **The tree view drifts, then GTK aborts.** Each part deleted this way removes another wrong row. The GTK tree no longer matches the model, and a later `ItemAdded()` can hit the `_gtk_rbtree_insert_after()` assertion. With Assemble that is the `ItemAdded()` for the merged object, right after the source objects are deleted.

### Evidence

The app was run under gdb with a breakpoint on `gtk_tree_path_append_index` when its index is negative. There were 16 hits in one session, all on this path:

```
gtk_tree_path_append_index (index -1)
 <- wxDataViewModel::ItemDeleted
 <- ObjectDataViewModel::Delete            (child)
 <- ObjectDataViewModel::Delete            (object)
 <- ObjectList::delete_object_from_list
 <- ObjectList::delete_from_model_and_list
 <- ObjectList::remove  <- ObjectList::merge            (Assemble)
    or Selection::erase <- Plater::remove_selected      (Delete key)
```

Backtrace of one of the aborts (stripped build, frames in `CrealityPrint` identified separately):

```
#5  _gtk_rbtree_insert_after ()                     libgtk-3.so.0
#6  gtk_tree_view_row_inserted ()                   libgtk-3.so.0
...
#13 wxDataViewModel::ItemAdded(wxDataViewItem const&, wxDataViewItem const&)
#14 ObjectDataViewModel::AddObject                  (via ObjectList::add_object_to_list <- ObjectList::merge)
...
#21 wxMenuBase::DoProcessEvent                      (context menu "Assemble")
```

## Fix

`src/slic3r/GUI/ObjectDataViewModel.cpp`, `ObjectDataViewModel::Delete()`, `itObject` branch:

- On GTK, the loop that deletes the object's children one by one is skipped.
- The `ItemDeleted(parent, object)` that already follows removes the object's row together with its subtree. GTK drops all child rows with it, whether or not wxGTK built them.
- The children are still freed: `~ObjectDataViewModelNode()` deletes its children.

```cpp
#ifndef __WXGTK__
            // Delete all sub-items
            int i = (*it)->GetChildCount() - 1;
            while (i >= 0) {
                Delete(wxDataViewItem((*it)->GetNthChild(i)));
                i = (*it)->GetChildCount() - 1;
            }
#else
            // On GTK, do not notify the sub-items one by one. ...
#endif
            m_objects.erase(it);
```

Why only on GTK: the per-child path works on the generic and macOS implementations, and the extra work it does there (settings items, volume counters, instance roots) only updates nodes that are about to be destroyed. Restricting the change to GTK keeps the other platforms exactly as they are.

## Not changed (possible follow-ups)

`ObjectDataViewModel::DeleteChildren()` and `DeleteVolumeChildren()` (used for example by "merge parts into one object") also send `ItemDeleted()` per child while keeping the parent, so they may hit the same `-1` on GTK. They did not show up in any of the captures above and are left as they are.

## Testing

Tested on Fedora 45, GNOME 50, Wayland, Flatpak (GNOME 50 runtime, LLVM 21), on the 7.3.2 sources; `ObjectDataViewModel.cpp` is identical on the current `master`.

- **Before:** two aborts in one evening while assembling objects from several imported `.3mf` files. Under gdb, 16 negative-index hits in one session, at every Assemble and every Delete of a multi-part object.
- **After:** over several days of normal use, including 16 deletions of three-part objects and Assemble on assemblies in one session: no `index_ >= 0` warning in the journal, no abort, no core dump.
- Single-part objects, plates and the rest of the object list behave as before.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
