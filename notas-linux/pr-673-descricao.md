# Description

## Summary

With CMake 4.x, the dependency build stops while configuring Boost 1.84. Boost.Locale calls `source_group(TREE .../include/boost/locale ...)` with a file list that also holds `include/boost/locale.hpp`, which is outside that tree, and CMake 4 rejects that. This PR patches that `CMakeLists.txt` before Boost is configured, the same way `apply-static-zstd-patch.cmake` already patches Boost.Iostreams on macOS.

Two files are changed: `deps/Boost/Boost.cmake` and the new `deps/Boost/apply-locale-source-group-patch.cmake`. The patch only affects how the Boost.Locale sources are grouped in IDE projects, not what is compiled.

## Symptom

Any dependency build with CMake 4.5 (the version in the Flathub GNOME 50 SDK since its 2026-11-19 update, `50.6-20`) fails at the Boost configure step:

```
CMake Error at libs/locale/CMakeLists.txt:231 (source_group):
  source_group
  ".../dep_Boost-prefix/src/dep_Boost/libs/locale/include/boost/locale"
  is not a prefix of file
  ".../dep_Boost-prefix/src/dep_Boost/libs/locale/include/boost/locale.hpp"

-- Configuring incomplete, errors occurred!
```

## Root cause

`libs/locale/CMakeLists.txt` in Boost 1.84:

```cmake
file(GLOB_RECURSE headers include/*.hpp)        # includes include/boost/locale.hpp
...
set(sources_inc ${sources})
list(FILTER sources_inc EXCLUDE REGEX "^src/")
source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}/src/boost/locale" PREFIX "sources" FILES ${sources_src})
source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}/include/boost/locale" PREFIX "headers" FILES ${sources_inc})   # line 231
source_group("headers" FILES "include/boost/locale.hpp")
```

`sources_inc` keeps `include/boost/locale.hpp`, which is not under `include/boost/locale/`. CMake 4 errors on a `source_group(TREE ...)` file outside the tree. The next line already groups `locale.hpp` on its own.

## Fix

- New script `deps/Boost/apply-locale-source-group-patch.cmake`. Right before that `source_group(TREE …/include/boost/locale …)` call, it inserts:

  ```cmake
  list(FILTER sources_inc INCLUDE REGEX "(^|/)include/boost/locale/")
  ```

  The script is idempotent: if the filter is already there, it does nothing. If the call is not found, for example in a newer Boost that fixed it, it only prints a status message and leaves the file alone.
- `deps/Boost/Boost.cmake` runs it as the Boost `PATCH_COMMAND` on all platforms. On macOS the existing zstd patch runs after it, as a second `COMMAND` of the same `PATCH_COMMAND`, and `DEPENDS dep_zstd` is kept.

## Testing

- **Linux:** a full dependency and app build inside the Flathub GNOME 50 SDK with CMake 4.5.0 (Flatpak, LLVM 21): Boost configured and built, and the app built and ran normally. Without the patch the same build stopped at the error above.
- The script was also run twice in a row on an extracted Boost 1.84 tree: the second run reported "already applied" and the file was unchanged.
- **macOS and Windows:** not built here. On macOS the zstd patch command is unchanged and now runs as the second command; on Windows the new script only changes how the Boost.Locale sources are grouped.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
