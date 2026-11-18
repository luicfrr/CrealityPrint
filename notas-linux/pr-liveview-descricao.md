# Description

## Summary

On Linux, opening the printer camera (liveview) in a second CrealityPrint window, while another window already has it open, closed the second window immediately with `SIGABRT`. It happened every time with the Flatpak build. The cause is the local UDP port that metaRTC picks for the WebRTC connection: inside a Flatpak sandbox, every instance picks the same one. This PR makes `WebRTCDecoder` ask the OS for a free UDP port before each connection.

One file is changed: `src/video/WebRTCDecoder.cpp` (+23 lines). Windows and macOS are not affected in practice: `WebRTCDecoder::startPlay()` is only called on Linux (`HttpServer.cpp`, under `#if defined(__linux__)`).

## Symptom

1. Open CrealityPrint, connect to a printer (here a Creality Hi at `192.168.100.30`) and open the camera view.
2. Open a second CrealityPrint window, for example by double-clicking a `.3mf` (`single_instance` is off), and open the camera view there.
3. The second window disappears. stderr shows:

   ```
   request for resource: /videostream?ip=192.168.100.30
   terminate called without an active exception
   ```

   and `systemd-coredump` records a `SIGABRT` for `/app/CrealityPrint`. The first window keeps working.

## Root cause

The crash is a chain of four steps:

1. **Same "random" port in every instance.** `WebRTCDecoder::WebRTCDecoder()` sets `avinfo.rtc.rtcLocalPort = 10000 + yang_random() % 15000`. `YangRtcReceive::init()` then uses that value as the local port of the connection (`streamconfig.localPort = m_context->avinfo.rtc.rtcLocalPort++`). metaRTC seeds `yang_random()` once, with `srandom(yang_update_system_time() | (getpid() << 13))` ([`YangMath.c`](https://github.com/CrealityOfficial/metartc/blob/v1.0.0/libmetartccore6/src/yangutil/sys/YangMath.c)). `yang_update_system_time` is a macro for `yang_get_system_micro_time()`, which counts **microseconds since its own first call**, so it is close to 0 on that first call. The seed is therefore almost only the pid. The `WebRTCDecoder` singleton is constructed during static initialization, so the call always happens at the same point of startup.

   Inside a Flatpak sandbox, the app's pid is the same in every instance (the main thread is LWP 2 in the core dumps). Every instance therefore draws the same port. Here that was UDP `12171`, which `ss -uanp` showed held by the first instance.

2. **metaRTC exits the process when `bind()` fails.** The UDP receive thread does:

   ```c
   // libmetartccore6/src/yangice/YangRtcSocket.c, yang_run_rtcudp_thread()
   if (yang_socket_listen(sock->fd, &sock->local_addr) < 0) {
       yang_error("Udp server bind error");
       exit(1);
   }
   ```

   ([`YangRtcSocket.c:75`](https://github.com/CrealityOfficial/metartc/blob/v1.0.0/libmetartccore6/src/yangice/YangRtcSocket.c#L75))

3. **`exit()` runs static destructors while other threads are alive.** One of them is the singleton in `UpdateParams::getInstance()` (`static UpdateParams instance;`). Its `std::thread m_check_thread` is still joinable, so `std::thread::~thread()` calls `std::terminate()`.

4. `std::terminate()` without an active exception prints `terminate called without an active exception` and aborts.

## Fix

`src/video/WebRTCDecoder.cpp`:

- New helper `find_free_udp_port()` (anonymous namespace). It opens a `boost::asio` UDP socket bound to port 0 on IPv4, reads the port the kernel assigned, and closes the socket. If the probe fails it returns 0.
- `WebRTCDecoder::startPlay()` calls it right before `m_player->playRtc()` and, when it returns a port, stores it in `m_context->avinfo.rtc.rtcLocalPort`. This is the value `YangRtcReceive::init()` copies into the connection's `localPort`.

```cpp
m_context->synMgr.session->playBuffer->resetVideoClock(m_context->synMgr.session->playBuffer->session);
if (const int32_t port = find_free_udp_port(); port > 0)
    m_context->avinfo.rtc.rtcLocalPort = port;
int32_t err = m_player->playRtc(0, const_cast<char*>(m_url.c_str()));
```

Why this approach:

- The port is chosen by the kernel among ports that are free at that moment, so two instances no longer collide. A collision with any other program holding the old fixed port is also avoided.
- No change to metaRTC, which is a prebuilt dependency (`deps/metartc`, tag `v1.0.0`). The WHEP path that the liveview uses (`connectWhipWhepServer` → `yang_whip_connectPeer`) does not override `localPort`. The other path that randomizes it (`yang_stream_parseUrl`) is not used by `YangRtcReceive::init(puid, url)`.
- If the probe fails, the previous behaviour is kept.
- The port is picked on every `startPlay()`, so reconnecting after `stopPlay()` also gets a free port.

The window between closing the probe socket and metaRTC binding the port is a few milliseconds. Another process would have to grab exactly that port in that window, which is far less likely than the old guaranteed collision.

## Not changed (possible follow-ups)

- metaRTC still calls `exit(1)` on a UDP bind failure, and in several other places (`YangRtcSocket.c`, `YangCTimer.c`, decoders, audio). Any such failure still closes the app. Returning an error from `yang_run_rtcudp_thread` would need a patch to the metaRTC dependency.
- `UpdateParams` (and possibly other singletons) still hold a joinable `std::thread` at static destruction. An `exit()` from any thread therefore turns into `SIGABRT` instead of a normal exit.
- metaRTC's `yang_random()` seed stays weak (pid plus microseconds since first call). It is also used for ICE credentials (`yang_cstr_random`).

# Screenshots/Recordings/Graphs

No UI change. Backtrace of the crashing thread, from the core dump of the installed (stripped) build, with frames 6 and 9 resolved against a non-stripped build of the same sources. Both binaries have identical segment layout.

```
#0  __pthread_kill_implementation ()        libc.so.6
#1  raise ()                                libc.so.6
#2  abort ()                                libc.so.6
#3  __gnu_cxx::__verbose_terminate_handler() libstdc++.so.6
#4  __cxxabiv1::__terminate(void (*)())     libstdc++.so.6
#5  std::terminate()                        libstdc++.so.6
#6  Slic3r::GUI::UpdateParams::~UpdateParams()     /app/CrealityPrint +0x49845b2
#7  __run_exit_handlers ()                  libc.so.6
#8  exit ()                                 libc.so.6
#9  yang_run_rtcudp_thread                  /app/CrealityPrint +0x783899c
#10 start_thread ()                         libc.so.6
#11 clone ()                                libc.so.6
```

The code right before frame 9's return address is `call yang_clog` (the "Udp server bind error" message) followed by `mov $0x1,%edi; call exit@plt`.

## Tests

Tested on Fedora 45, GNOME 50, Wayland, Flatpak (GNOME 50 runtime, LLVM 21), with a Creality Hi on the local network:

- **Before:** with one window streaming the camera, opening the camera in a second window crashed that window every time (two core dumps, both with the trace above).
- **After:** both windows open and show the camera at the same time, and no crash or core dump.
- Single-window liveview still connects and streams as before.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
