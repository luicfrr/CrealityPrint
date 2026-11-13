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

Para compilar e gerar o Flatpak:

```bash
./flatpak/build-fedora.sh
```

Quando o branch do PR receber commits novos, traga-os para cá:

```bash
git merge fix/linux-gnome-and-project-presets
```
