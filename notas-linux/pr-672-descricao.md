# Description

## Summary

Closing CrealityPrint sometimes crashed it with `SIGSEGV` in the auto-backup thread. The window was already gone, so users only notice it from the crash report or core dump. The backup thread called a copy of the post callback that it took before running the backup, after `MainFrame::shutdown()` had already cleared the callback and the frame had been destroyed. This PR makes the thread call the callback as it is at the moment of the call.

One file is changed: `src/libslic3r/Format/bbs_3mf.cpp` (+5 / −3 lines). The code is shared by all platforms; the crash was seen on Linux.

## Symptom

Close CrealityPrint, especially shortly after changing the project, when an auto-backup is due. Sometimes `systemd-coredump` records a `SIGSEGV` for `/app/CrealityPrint`, in a secondary thread:

```
#0  0x0000000000000000 in ?? ()
#1  std::_Function_handler<void (int), Slic3r::GUI::MainFrame::MainFrame()::$_1>::_M_invoke(std::_Any_data const&, int&&)
#2  Slic3r::_BBS_Backup_Manager::operator()()
#3  boost::(anonymous namespace)::thread_proxy(void*)
#4  start_thread ()
#5  clone ()
```

A second occurrence, under gdb, was a `SIGSEGV` at `0x20` in a secondary thread right after the window was closed. gdb did not record a backtrace for it, so it is likely, but not confirmed, to be the same thread.

## Root cause

- `MainFrame` registers a backup callback in its constructor (`MainFrame.cpp`, `Slic3r::set_backup_callback([this](int action) { ... })`). For `action == 0` it calls `wxPostEvent(this, ...)`.
- `MainFrame::shutdown()` clears it with `Slic3r::set_backup_callback(nullptr)` before the frame is destroyed. `set_post_callback()` takes the backup manager's mutex.
- The backup thread loop (`_BBS_Backup_Manager::operator()`) did:

  ```cpp
  m_tasks.pop_front();
  auto callback = m_post_callback;   // copy taken here
  lock.unlock();
  process_task(t);                   // backup runs without the lock
  lock.lock();
  if (t.type > None) {
      m_ui_tasks.push_back(t);
      if (m_ui_tasks.size() == 1 && callback)
          callback(0);               // calls the copy
  }
  ```

  If the app is closed while `process_task()` runs, `shutdown()` clears `m_post_callback`, but the thread still calls the copy taken before it. The lambda then posts an event to the destroyed `MainFrame`, and the call through the freed object lands at an invalid address (`0x0` in the backtrace above).

## Fix

Call `m_post_callback` as it is when the thread takes the lock again, instead of the copy:

```cpp
m_tasks.pop_front();
lock.unlock();
process_task(t);
lock.lock();
if (t.type > None) {
    m_ui_tasks.push_back(t);
    if (m_ui_tasks.size() == 1 && m_post_callback)
        m_post_callback(0);
}
```

- The call happens with the mutex held, and `set_post_callback()` takes the same mutex. Once `shutdown()` has cleared the callback, it is never called again.
- If a call is in progress when `shutdown()` runs, `set_post_callback(nullptr)` waits for it. The frame still exists at that point, because `shutdown()` runs before it is destroyed.
- No deadlock is added. For `action == 0` the callback only calls `wxPostEvent()`, which does not take the backup mutex, and the thread already held the mutex when it called the copy before.
- The `Backup` UI task (`process_ui_task()`), which takes its own copy before calling with `action == 1`, runs on the UI thread and is not changed.

## Testing

Tested on Fedora 45, GNOME 50, Wayland, Flatpak (GNOME 50 runtime, LLVM 21), on the 7.3.2 sources; the backup loop is identical on the current `master`.

- **Before:** two crashes on exit in one evening: the core dump above, and the `0x20` jump under gdb.
- **After:** over four days the app was opened and closed about 30 times, including right after editing projects, with no core dump.

The crash depends on timing (closing while a backup runs), so the absence of crashes is good evidence but not proof. The reasoning above does not depend on timing.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
