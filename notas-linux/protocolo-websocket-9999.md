# Protocolo WebSocket da porta 9999 (impressoras Creality)

A aba Dispositivo do Creality Print é um app web compilado e minificado (`resources/web/deviceMgr/assets/*.js`), sem o código-fonte no repositório. Ele conversa com a impressora por um WebSocket em `ws://<ip>:9999`. A lista abaixo foi extraída desse bundle (versão 7.x) quando estudamos levar estes recursos para o OrcaSlicer, e serve de referência se um dia você quiser mexer na aba Dispositivo ou no CFS.

Na Creality Hi, o mesmo WebSocket é usado para ler os slots do CFS (`boxsInfo`) e iniciar impressões.

Formato: `{"method":"set","params":{<comando>:<valor>}}` e `{"method":"get","params":{<consulta>:1}}`.

```text
modifyMaterial {boxId, boxType, id, rfid, type, vendor, name, color:"#0RRGGBB", minTemp, maxTemp, pressure}
               (reset: rfid/type/vendor/name/color vazios, temps 0)
feedInOrOut    {boxId, materialId, isFeed:0|1}
refreshBox     {boxId, materialId}
boxConfig      {autoRefill, cAutoFeed, cSelfTest, ignoreColorAutoFeed}   (CFS-Lite: só cAutoFeed, autoRefill)
dryBox         {addr, num, dryMode, targetTemp, totalTime, materialType:[...]}  (dryMode 0 = parar)
setNozzleInfo  {id, diameter, flow, texture}
colorMatch, multiColorPrint, enableSelfTest, opGcodeFile        (iniciar impressão)
pause, stop, autohome, setPosition, gcodeCmd, speedMode, setFeedratePct
nozzleTempControl, bedTempControl, boxTempControl
fan, modelFanPct, auxiliaryFanPct, caseFanPct, fanCase, fanAuxiliary, lightSw, led
excludeObjects, errorHandling, cleanErr, repoPlrStatus, deleteLocalFiles, deleteHistory
videoElapse, ctrlVideoFiles, hostname, sleepMode, replaceCutter, autoDry, ignoreColorToRefill

get: boxsInfo, boxConfig, cfsInfo, cfsList, reqMaterials, materialBinStatus, reqGcodeFile, reqHistory,
     pFileList, printObjects, reqPrintObjects, reqExcludeObjectImages, reqElapseVideoList,
     nozzleList, nozzleState, nozzleFilament, spaceInfo, allPrintTime, queryParseGCode
```

HTTP: `/downloads/gcode/`, `/downloads/humbnail/` (miniaturas), `/downloads/video/` (timelapse), `/downloads/original/current_print_image`.
Câmera: K1 `http://<ip>:8080/?action=stream`; K2 `http://<ip>:8000/call/webrtc_local` (ou HTTPS com `videoInfo.videoEncryption`).

O protocolo pode ser usado livremente (é interoperabilidade). O bundle minificado não é a forma de código-fonte que a licença pede, então não copie código dele: reimplemente a partir do comportamento observado e do código C++ do próprio Creality Print (AGPL-3.0).
