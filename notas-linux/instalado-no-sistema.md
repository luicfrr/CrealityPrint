# O que foi instalado para compilar os slicers

Use esta lista para limpar o sistema depois. Os comandos de remoção estão no fim de cada seção.

A parte do OrcaSlicer vem do antigo repositório `luicfrr/slicers`, que foi abandonado. Ela fica aqui para você poder limpar o build do Orca mesmo depois de apagar aquele repositório.

## OrcaSlicer (build nativo)

### Pacotes do Fedora (dnf)

Instalados numa única transação, a **98** do `dnf history` (12/11/2026, 17:07), com `./build_linux.sh -u`. São os 33 pacotes de `scripts/linux.d/fedora` que ainda faltavam, mais as dependências que eles puxaram: 346 pacotes no total, quase todos `-devel`.

Pedidos explicitamente: autoconf, automake, cmake, dbus-devel, eglexternalplatform-devel, extra-cmake-modules, gcc, gcc-c++, gstreamer1-devel, gstreamermm-devel, gtk3-devel, libcurl-devel, libmspack-devel, libquadmath-devel, libsecret-devel, libspnav-devel, libtool, m4, mesa-libGL-devel, nasm, ninja-build, openssl-devel, perl, texinfo, wayland-protocols-devel, webkit2gtk4.1-devel, yasm.

Já estavam no sistema e **não** fazem parte da transação: file, gettext, git, pkgconf e os plugins do GStreamer (good, good-gtk, bad-free).

Para conferir o que entrou:

```bash
dnf history info 98
```

Para desfazer a transação inteira (remove só o que ela instalou):

```bash
sudo dnf history undo 98
```

> O `gcc`, o `git` e o `cmake` costumam ser úteis fora do build. Se quiser mantê-los, remova os pacotes à mão em vez de usar o `undo`.

### Arquivos do build

| Caminho | Tamanho | O que é |
|---|---|---|
| `OrcaSlicer-main/deps/build` | 7,0 GB | dependências compiladas (Boost, wxWidgets, OCCT, CGAL...) |
| `OrcaSlicer-main/build` | 9,6 GB | o app e os testes |
| `~/.config/OrcaSlicer` | pequeno | configuração do Orca compilado (presets, logs) |

Se você apagar o clone local do `slicers` inteiro, isso já some junto. Para apagar só o build:

```bash
rm -rf ~/Documentos/Projetos/slicers/OrcaSlicer-main/deps/build ~/Documentos/Projetos/slicers/OrcaSlicer-main/build
```

Para apagar também a configuração do Orca compilado:

```bash
rm -rf ~/.config/OrcaSlicer
```

## CrealityPrint (Flatpak)

Nada aqui usa `sudo`: tudo foi instalado como usuário (`--user`).

### Flatpaks de usuário

| Ref | Por quê |
|---|---|
| `org.flatpak.Builder` | o flatpak-builder em si, já que o `sudo dnf install flatpak-builder` pediria senha |
| `org.freedesktop.Sdk//26.08` (+ `.Locale`) | runtime do `org.flatpak.Builder`, instalado junto com ele |
| `org.gnome.Sdk//50` (+ `.Locale`) | SDK que o manifesto usa para compilar (instalado pelo builder com `--install-deps-from=flathub`) |
| `org.freedesktop.Sdk.Extension.llvm21` | Clang/LLD que o manifesto usa (idem) |

O `org.gnome.Platform//50` já estava instalado, porque é o runtime do CrealityPrint do Flathub. Não remova esse.

Para remover os quatro:

```bash
flatpak uninstall --user org.flatpak.Builder org.gnome.Sdk//50 org.freedesktop.Sdk.Extension.llvm21
```

```bash
flatpak uninstall --user --unused
```

O segundo comando remove o `org.freedesktop.Sdk//26.08` e os `.Locale`, que ficam sem uso.

### Arquivos do build

| Caminho | O que é |
|---|---|
| `~/.cache/crealityprint-flatpak/` | estado do flatpak-builder (downloads, cache do ccache, módulos compilados), o repositório local e o bundle `CrealityPrint-dev.flatpak` |
| `~/.cache/crealityprint-flatpak-build.log` | log do último build |

```bash
rm -rf ~/.cache/crealityprint-flatpak ~/.cache/crealityprint-flatpak-build.log
```

O script que gera tudo isso é [`flatpak/build-fedora.sh`](../flatpak/build-fedora.sh).
