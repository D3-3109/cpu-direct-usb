# CPU Direct USB · 中文版

扫描 Windows USB 控制器与外设拓扑，直观查看鼠标、键盘、手柄等输入设备到 CPU 之间经过了几层芯片（**0 芯片直连 / 1 芯片 / 2+ 芯片**），并提供 MSI 中断与 USB 选择性挂起快捷优化。

## 一行运行

在 Windows 10/11 的 PowerShell 中复制运行：

```powershell
$wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.DownloadString('https://raw.githubusercontent.com/D3-3109/cpu-direct-usb/main/cpudirect.ps1') | iex
```

也可以直接下载单个 [`cpudirect.ps1`](cpudirect.ps1) 本地运行：

```powershell
.\cpudirect.ps1
```

- **普通权限**：直接扫描拓扑，换插主板其他 USB 接口后输入 `R` 即可秒级重扫对比，快速找出真正的 `0 芯片` CPU 直连口。
- **管理员权限**：额外支持输入序号单项优化，或输入 `A` 一键开启控制器 MSI 中断并关闭 USB 选择性挂起。

## 拓扑说明

- **0 芯片（直连 CPU）**：输入设备直连 CPU 内置 USB 控制器（不经芯片组或外部/板载集线器），链路最短。
- **1 芯片**：经过主板芯片组（PCH / FCH），或虽连在 CPU 控制器上但中间经过了 1 级板载/外接 USB 集线器芯片（如 `ASM107x`）。
- **2+ 芯片**：经过多级集线器、显示器/扩展坞或芯片组 + 集线器组合。
- **精准过滤**：自动合并复合设备的多个子接口、保留同型号多台独立设备，并过滤主板 RGB 灯控等非输入类纯厂商 HID 设备。

## 离线测试

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tests\Run.Tests.ps1
```

测试全程模拟 PnP、注册表与 `powercfg`，不读取或修改本机设置。

---

致谢原项目：[MariusHeier/cpu-direct-usb](https://github.com/MariusHeier/cpu-direct-usb) · [MIT 许可证](LICENSE)
