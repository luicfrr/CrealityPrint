# Crashes da lista de objetos, do fechamento e do build com CMake 4.5

Investigação de 23/11/2026, no `linux-dev`. São três correções, todas commitadas neste branch e enviadas ao repositório oficial em PRs separados, cada um a partir do `master` oficial (`9c930d82`): [671](https://github.com/CrealityOfficial/CrealityPrint/pull/671) (`fix/linux-object-list-delete`), [672](https://github.com/CrealityOfficial/CrealityPrint/pull/672) (`fix/backup-callback-on-exit`) e [673](https://github.com/CrealityOfficial/CrealityPrint/pull/673) (`fix/boost-locale-cmake4`).

| Correção | Arquivo | Estado |
|---|---|---|
| 1. Crash ao fazer "Assemble" ou apagar objetos com várias partes | `src/slic3r/GUI/ObjectDataViewModel.cpp` | Testada; enviada no PR 671 |
| 2. Crash ao fechar o app (thread de backup) | `src/libslic3r/Format/bbs_3mf.cpp` | Sem crash em ~30 fechamentos; enviada no PR 672 |
| 3. Build quebrado pelo CMake 4.5 do GNOME SDK | `deps/Boost/Boost.cmake`, `deps/Boost/apply-locale-source-group-patch.cmake` | Testada: o build completo passou; enviada no PR 673 |

## 1. Crash da lista de objetos ("Assemble" / apagar objeto)

### Sintoma
Ao juntar dois objetos "Assembly" com **Assemble** (menu de contexto), o app às vezes fechava com:

```
gtk_tree_path_append_index: assertion 'index_ >= 0' failed
Gtk:ERROR:../gtk/gtkrbtree.c:471:_gtk_rbtree_insert_after: assertion failed: (_gtk_rbtree_is_nil (tree->root))
```

Isso aconteceu duas vezes, às 21:04 e às 21:08 de 23/11, com vários `.3mf` de Natal importados no mesmo projeto. O crash é intermitente, mas o aviso `index_ >= 0` aparece **sempre** que se apaga um objeto com várias partes, tanto pelo "Assemble" quanto pela tecla Delete.

### Causa
- A lista de objetos é desenhada com ImGui, mas o `ObjectList` continua sendo uma `wxDataViewCtrl`, ou seja, uma `GtkTreeView` ligada ao `ObjectDataViewModel`. Como essa árvore GTK nunca é expandida, o wxGTK nunca monta os filhos (as partes) de cada objeto no lado dele, porque a montagem é preguiçosa.
- Ao apagar um objeto, `ObjectDataViewModel::Delete()` primeiro apagava **cada filho** e mandava `ItemDeleted(objeto, filho)` para cada um.
- Para um filho que não conhece, o wxGTK recebe `-1` de `GetIndexOf()`. O caminho enviado ao GTK fica sendo o do **próprio objeto**, e `gtk_tree_model_row_deleted()` apaga a linha errada.
- Cada parte apagada corrompe mais a `GtkTreeView`. Às vezes o `ItemAdded()` seguinte, como o do objeto mesclado no "Assemble", aborta dentro do GTK.

A causa foi capturada no gdb com um breakpoint em `gtk_tree_path_append_index` quando o índice é negativo. Foram 16 capturas, todas por este caminho:

```
gtk_tree_path_append_index(-1)
 <- wxDataViewModel::ItemDeleted
 <- ObjectDataViewModel::Delete            (filho)
 <- ObjectDataViewModel::Delete            (objeto)
 <- ObjectList::delete_object_from_list
 <- ObjectList::delete_from_model_and_list
 <- ObjectList::remove  <- ObjectList::merge            ("Assemble")
    ou Selection::erase <- Plater::remove_selected      (tecla Delete)
```

### Correção
Em `ObjectDataViewModel::Delete()`, no ramo `itObject`, quando compilado para GTK (`#ifdef __WXGTK__`) os filhos não são mais apagados e notificados um por um. O único `ItemDeleted(prato, objeto)` que já existia remove a linha com toda a subárvore, e o destrutor de `ObjectDataViewModelNode` libera os filhos. Windows e macOS continuam como antes.

### Teste
De 23/11 a 27/11, com o build corrigido: "Assemble" de "Assembly" sem crash, e numa sessão de 24/11, 16 objetos de três partes apagados. Não apareceu nenhum `index_ >= 0` no journal (antes aparecia a cada exclusão dessas), nenhum abort e nenhum core dump.

### Falta
- `DeleteChildren()` e `DeleteVolumeChildren()`, usado por exemplo em "juntar partes num objeto", também notificam filho por filho e devem ter o mesmo problema no GTK. Elas não apareceram em nenhuma captura e não foram alteradas.
- PR no repositório oficial: [671](https://github.com/CrealityOfficial/CrealityPrint/pull/671), criado a partir do `master` oficial (`9c930d82`), onde `ObjectDataViewModel.cpp` é idêntico. A descrição está em [`pr-671-descricao.md`](pr-671-descricao.md).

## 2. Crash ao fechar o app (thread de backup)

### Sintoma
Às vezes, ao fechar o app, aparece um `SIGSEGV` numa thread secundária. O usuário não vê nada, porque a janela já fechou, mas o systemd registra um core dump. Aconteceu às 22:30 e às 22:36 de 23/11.

```
#0  0x0000000000000000 in ?? ()
#1  std::_Function_handler<void (int), Slic3r::GUI::MainFrame::MainFrame()::$_1>::_M_invoke
#2  Slic3r::_BBS_Backup_Manager::operator()()
#3  boost::thread_proxy
```

### Causa
O loop da thread de backup (`_BBS_Backup_Manager::operator()` em `bbs_3mf.cpp`) copiava o callback (`auto callback = m_post_callback;`), soltava o lock, fazia o backup e depois chamava **a cópia**. Ao fechar, `MainFrame::shutdown()` limpa o callback com `set_backup_callback(nullptr)`, mas a thread ainda tinha a cópia antiga. Ela chamava `wxPostEvent(this, …)` numa `MainFrame` já destruída, e a chamada virtual caía em `0x0` ou `0x20`.

### Correção
No momento da chamada, que já acontece com o lock pego, a thread usa o `m_post_callback` atual em vez da cópia. Depois que `shutdown()` limpa o callback, ele não é mais chamado. Se uma chamada estiver em andamento, `set_post_callback()` espera o lock, e a janela ainda existe.

### Teste
De 23/11 a 27/11 o app foi aberto e fechado cerca de 30 vezes sem nenhum core dump. Antes eram dois crashes ao fechar na mesma noite. Como depende de timing (fechar durante um backup), isso é um bom indício, não uma prova. PR: [672](https://github.com/CrealityOfficial/CrealityPrint/pull/672), descrição em [`pr-672-descricao.md`](pr-672-descricao.md).

## 3. Build quebrado pelo CMake 4.5 (GNOME SDK de 19/11)

### Sintoma
Depois da atualização do `org.gnome.Sdk//50` em 19/11 (`50.6-20`), que traz o CMake 4.5, qualquer build parava na configuração do Boost 1.84:

```
CMake Error at libs/locale/CMakeLists.txt:231 (source_group):
  source_group ".../libs/locale/include/boost/locale" is not a prefix of file
  ".../libs/locale/include/boost/locale.hpp"
```

### Correção
`deps/Boost/apply-locale-source-group-patch.cmake` é aplicado como `PATCH_COMMAND` do Boost em todas as plataformas, antes do patch de zstd no macOS. Antes do `source_group(TREE …/include/boost/locale …)`, ele insere um `list(FILTER sources_inc INCLUDE REGEX "(^|/)include/boost/locale/")`. O script é idempotente e não faz nada se a linha não existir, por exemplo numa versão mais nova do Boost.

Enviada ao repositório oficial no PR [673](https://github.com/CrealityOfficial/CrealityPrint/pull/673), porque qualquer build com CMake ≥ 4.5 bate nesse erro. A descrição está em [`pr-673-descricao.md`](pr-673-descricao.md). No macOS e no Windows não foi compilada.

## Como foi investigado (para retomar)

- **Build local com ccache e símbolos:** `~/.cache/crealityprint-flatpak/mk_local_manifest.py` gera `flatpak/io.github.crealityofficial.CrealityPrint.local.yml`, fora do git e listado em `.git/info/exclude`. Esse manifesto liga o ccache (`CMAKE_*_COMPILER_LAUNCHER=ccache`) no `creality_deps` e no app. Os wrappers de ccache do flatpak-builder não cobrem o `clang`, por isso sem isso o ccache não era usado. Para depurar, o app foi compilado com `CXXFLAGS="-g1"` e `--target install` (sem strip). O bundle está em `~/.cache/crealityprint-flatpak/CrealityPrint-debug.flatpak` e é **o que está instalado agora**. Para voltar a um build normal, gere o manifesto local de novo e compile.
- **gdb no Flatpak:** `~/.cache/crealityprint-flatpak/cores/catch-bad-index.gdb` roda o app com breakpoints no índice negativo do GTK e em `SIGABRT` e `SIGSEGV`:

  ```bash
  flatpak run --devel --env=LC_ALL=C.UTF-8 --command=gdb --filesystem=$HOME/.cache/crealityprint-flatpak io.github.crealityofficial.CrealityPrint -batch -x $HOME/.cache/crealityprint-flatpak/cores/catch-bad-index.gdb /app/CrealityPrint > $HOME/.cache/crealityprint-flatpak/cores/gdb-session.log 2>&1
  ```

  As capturas antes da correção estão em `cores/gdb-session-before-fix.log`.
- **Core dumps:** `coredumpctl list`, depois `coredumpctl dump <pid> -o arquivo` e `gdb` dentro de `flatpak run --devel`. Os do sistema ficam em `/var/lib/systemd/coredump` e são apagados pelo próprio systemd.
