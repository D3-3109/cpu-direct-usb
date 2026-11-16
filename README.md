# CPU Direct USB · 中文版

查看 Windows USB 输入设备连接到了哪个控制器，以及中间经过了几级集线器。

## 一行运行

在 Windows 10/11 的 PowerShell 中复制运行：

```powershell
(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/D3-3109/cpu-direct-usb/main/cpudirect.ps1') | iex
```

直接运行本仓库的单个 `cpudirect.ps1`，无需安装或下载其他模块。命令使用 `DownloadString`，保证 Windows PowerShell 5.1 正确读取中文。

运行后显示控制器、输入设备和连接路径，最后列出可选设置。普通权限即可扫描；需要修改时，以管理员身份运行同一命令，输入序号执行一项，直接回车跳过。

也可以只下载 [cpudirect.ps1](cpudirect.ps1)，在 PowerShell 中运行 `.\cpudirect.ps1`。

## 结果说明

- 控制器归属根据型号表推测；未收录的型号显示未知，Thunderbolt 和第三方控制器不直接判成 CPU 直连。
- 控制器类别与集线器层数分开显示，CPU 后接集线器仍属于 CPU 控制器；根集线器不计入额外层数。
- 同型号的不同设备分别保留，同一复合设备的输入接口合并显示。
- 没有输入设备使用 CPU 控制器，不代表没有直连端口。更换插孔后重新运行，结合主板手册比较。

工具不测量输入延迟。可选设置包括 MSI、控制器及电源计划的 USB 选择性挂起；MSI 需硬件与驱动支持，关闭挂起会增加功耗，效果取决于设备。只有选择菜单项后才会修改，写入失败会明确报错。

## 开发测试

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tests\Run.Tests.ps1
```

测试模拟设备、注册表和电源命令，不修改本机设置。

原项目：[MariusHeier/cpu-direct-usb](https://github.com/MariusHeier/cpu-direct-usb)。型号表沿用上游；[MIT 许可证](LICENSE)。
