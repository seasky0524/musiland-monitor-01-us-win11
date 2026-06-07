# MUSILAND Monitor 01 US Windows 11 一键安装

优先双击运行：

```text
Install-MUSILAND-Monitor01US-Win11.cmd
```

请先把原厂安装包放到同目录：

```text
MlCyMon_2.4.2.1_build20131204.exe
```

脚本会自动提取原厂 payload，然后依次安装 firmware、bus、audio 驱动，以及原厂控制面板和 `MlCyMonSvc` 服务。

如果驱动已经正常，只是耳机口没有声音，可以只双击运行：

```text
Install-MUSILAND-ControlPanel-Win11.cmd
```

安装完成后，在 Windows 声音输出里选择 `扬声器 (MUSILAND Monitor 01 US)`。`SPDIF 接口` 只用于数字同轴/光纤输出，不是耳机口。
