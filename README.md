# MUSILAND Monitor 01 US Windows 11 一键安装脚本

这个仓库用于让老款 `MUSILAND Monitor 01 US` USB 声卡在 Windows 11 上继续使用，也适用于搜索 `乐之邦 Monitor 01 US`、`MUSILAND Monitor Series(USB)`、`MlCyMon`、`MUAUDIO`、`Win11 USB Audio Driver` 等关键词的用户。

## 搜索关键词

`MUSILAND Monitor 01 US` / `乐之邦 Monitor 01 US` / `MUSILAND Monitor Series USB` / `Windows 11 driver` / `Win11 x64` / `USB Audio Driver` / `MlCyMon` / `MlCyMonBus` / `MlCyMonSvc` / `MUAUDIO` / `USB\VID_04B4&PID_5135` / `USB\VID_04B4&PID_5125` / `ASIO` / `WASAPI` / `DirectSound` / `QQ音乐切歌无声`

已验证的设备链路：

- firmware 模式：`USB\VID_04B4&PID_5125`
- bus 模式：`USB\VID_04B4&PID_5135`
- audio 子设备：`MUAUDIO\VID_04B4&PID_5135`
- Windows 输出端点：`扬声器 (MUSILAND Monitor 01 US)`

## 重要说明

仓库只放脚本，不直接分发原厂驱动二进制文件。请自行准备原厂安装包：

```text
MlCyMon_2.4.2.1_build20131204.exe
```

把这个 EXE 放到本仓库目录下，再运行一键安装脚本。脚本会从原厂 EXE 中自动提取 x64 MSI/CAB、准备驱动文件、安装驱动、安装原厂控制面板和 `MlCyMonSvc` 服务。

## 使用方法

1. 下载或 clone 本仓库。
2. 把 `MlCyMon_2.4.2.1_build20131204.exe` 放到仓库根目录。
3. 右键或双击运行：

```text
Install-MUSILAND-Monitor01US-Win11.cmd
```

脚本会弹出 UAC 管理员授权，然后自动执行：

1. 从原厂 EXE 准备 `prepared-driver` payload。
2. 安装 firmware 驱动。
3. 安装 bus 驱动。
4. 安装 audio 驱动。
5. 安装原厂控制面板和 `MlCyMonSvc` 自动启动服务。

安装完成后，在 Windows 声音输出里选择：

```text
扬声器 (MUSILAND Monitor 01 US)
```

`SPDIF 接口` 只用于数字同轴/光纤输出，不是耳机口。

## 驱动已装但没声音

如果设备管理器里驱动已经正常，但耳机口没有声音，通常是缺少原厂控制面板/后台服务。可以只运行：

```text
Install-MUSILAND-ControlPanel-Win11.cmd
```

它会安装：

- `MlCyMonApp.exe`
- `MlCyMonSvc.exe`
- Qt 运行库
- ASIO DLL
- 必要注册表项和自动启动服务

## QQ 音乐切歌后无声

如果 QQ 音乐使用 `DS: 主声音驱动程序` 时，第一首歌正常，切到下一首后耳机里只有电流底噪、没有音乐声，而其他视频/播放器也跟着无声，可以在 QQ 音乐的输出设备里改用：

```text
WASAPI: 主声音驱动程序
```

`ASIO: MUSILAND Monitor Series(USB)` 通常也能正常播放，但它会固定到 MUSILAND 设备，不适合需要跟随 Windows 默认输出设备切换的场景。`WASAPI: 主声音驱动程序` 仍然会跟随系统默认输出设备，比老的 `DS: 主声音驱动程序` 更适合 Windows 10/11 的共享音频路径。

建议同时把 `DSD优选模式` 设置为 `仅使用PCM模式`。如果仍有切歌异常，可以把 QQ 音乐里的音频缓冲适当调大，例如 `1000ms` 到 `2000ms`。

## 测试签名

不需要启用 Windows 测试签名。本方案使用原厂已签名驱动文件，并补齐 firmware、bus、audio、控制服务这几段安装链路。

## 日志

主安装日志会写到：

```text
Install-MUSILAND-Monitor01US-Win11.log
```

## 给维护者

提取流程在 `Prepare-MUSILAND-Payload.ps1` 中：

1. 从 EXE 的 PE resource type `40` / name `X64` 导出内嵌 MSI。
2. 从 MSI `_Streams` 表导出 `Setup.cab`。
3. 用 Windows 自带 `extrac32.exe` 解出 payload。
4. 生成 `prepared-driver` 下的一套规范驱动目录。
