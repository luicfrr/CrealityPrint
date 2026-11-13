# Notas do build local no Linux

Este branch (`linux-dev`) parte de `fix/linux-gnome-and-project-presets`, o branch do PR com as correções para Linux/GNOME, e acrescenta só o que é de uso local. Nada daqui vai para o PR.

| Arquivo | O que é |
|---|---|
| [`creality-print-correcoes.md`](creality-print-correcoes.md) | Os 7 problemas corrigidos, a causa de cada um e como compilar |
| [`instalado-no-sistema.md`](instalado-no-sistema.md) | Pacotes e arquivos instalados para os builds (CrealityPrint e o antigo OrcaSlicer), com os comandos para remover |
| [`diagnostico-project-preset.patch`](diagnostico-project-preset.patch) | Logs `[PROJECT_PRESET]` usados para achar o problema dos presets perdidos |
| [`images/`](images) | Capturas do visual GNOME (botões e cantos) |
| [`../flatpak/build-fedora.sh`](../flatpak/build-fedora.sh) | Gera o Flatpak no Fedora sem sudo |
| `../resources/printers/version.txt` | Versão dos perfis; o `.gitignore` do projeto o deixa de fora, e sem ele o app fechava ao abrir |

## Build do zero (Fedora)

Tudo roda em Flatpak, como usuário: não precisa de `sudo` nem de pacotes `-devel` no sistema. A primeira vez leva de 2 a 4 horas (as dependências, como OpenCV, OCCT e CGAL, são compiladas dentro do SDK) e usa cerca de 30 GB em `~/.cache/crealityprint-flatpak`. As seguintes reaproveitam esse cache e levam minutos.

1. Flathub e o flatpak-builder (uma vez só):

   ```bash
   flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
   ```

   ```bash
   flatpak install --user -y flathub org.flatpak.Builder
   ```

2. Código (o submódulo `UnitTest` aponta para um servidor interno da Creality e não é necessário):

   ```bash
   git clone --filter=blob:none -b linux-dev https://github.com/luicfrr/CrealityPrint.git
   ```

   ```bash
   cd CrealityPrint
   ```

3. Compilar. Na primeira execução, o GNOME SDK 50 e o LLVM 21 são baixados do Flathub:

   ```bash
   ./flatpak/build-fedora.sh
   ```

   `JOBS` é o número máximo de compilações simultâneas, incluindo dentro de cada dependência. Cada uma usa de 2 a 4 GB nos arquivos mais pesados (OpenCV, OCCT, CGAL):

   | `JOBS` | Pico de memória do build | Quando usar |
   |---|---|---|
   | 1 | cerca de 4 GB | usando o PC para outras coisas ao mesmo tempo (mais lento: a primeira vez pode passar de 8 horas) |
   | 2 | cerca de 8 GB | uso leve do PC |
   | 4 (padrão) | cerca de 14 GB | PC livre, 16 GB de RAM |

   ```bash
   JOBS=1 ./flatpak/build-fedora.sh
   ```

   Pode interromper com Ctrl+C e rodar de novo depois. Os módulos já concluídos ficam no cache, e o ccache reaproveita o que já foi compilado dentro do módulo interrompido.

4. Instalar e abrir. O bundle tem o mesmo ID do Creality Print do Flathub, então substitui a instalação de usuário:

   ```bash
   flatpak install --user -y ~/.cache/crealityprint-flatpak/CrealityPrint-dev.flatpak
   ```

   ```bash
   flatpak run io.github.crealityofficial.CrealityPrint
   ```

   A configuração (`Creality Print/7.3`) e os presets são os mesmos da versão oficial.

**Recomeçar do zero de verdade** (descarta o cache e recompila também as dependências):

```bash
rm -rf ~/.cache/crealityprint-flatpak
```

**Voltar para a versão oficial:**

```bash
flatpak install --user -y --reinstall flathub io.github.crealityofficial.CrealityPrint
```

**Problemas comuns:**
- *`runtime/org.freedesktop.Sdk/x86_64/<versão> não instalado`*: falta o runtime do `org.flatpak.Builder`, normalmente porque um `flatpak uninstall --unused` o removeu. Instale a versão que o erro mostra, por exemplo `flatpak install --user -y flathub org.freedesktop.Sdk//26.08`. Se ela não existir no Flathub, rode `flatpak update --user -y org.flatpak.Builder`.
- *Falta de memória* (processo encerrado, sistema travando): reduza os jobs com `JOBS=2`.
- *`Could not parse version string` ao abrir*: falta o `resources/printers/version.txt`. Ele está neste branch, mas some se você copiar o código sem o git (o `.gitignore` do projeto o ignora).

Quando o branch do PR receber commits novos, traga-os para cá:

```bash
git merge fix/linux-gnome-and-project-presets
```
