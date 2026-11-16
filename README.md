# CPU Direct USB · 简体中文修订版

用于查看 Windows USB 控制器、输入设备及经过的 USB 集线器。本版修复了设备去重、路径标签、空闲控制器判断和设置失败处理，并将界面与操作说明改为简体中文。

**默认只读扫描。控制器归属是型号表提供的推测，不是实测延迟，也不是主板布线的最终证明。** 设备名、芯片型号、硬件 ID 和系统返回的错误信息保留原文，便于核对。

## 一行启动

在 Windows PowerShell 5.1 中复制运行（普通权限即可扫描）：

```powershell
irm https://raw.githubusercontent.com/D3-3109/cpu-direct-usb/main/run.ps1 | iex
```

命令从本仓库获取启动器，再把同一固定提交的主脚本和三个 `lib` 模块下载到独立临时目录，全部通过 SHA256 校验后启动，默认只读扫描。文件目录会显示在终端中，运行后保留，便于查看源码或再次使用。`main/run.ps1` 会随仓库更新；内置校验保证运行文件与启动器清单一致，不替代对仓库来源的信任。

启动器不请求提权，只为新开的 PowerShell 子进程指定 `-ExecutionPolicy Bypass`，不修改用户或系统执行策略；子进程继承当前终端已有权限，组织策略仍可能阻止运行。下载失败或校验不匹配时不会执行分析脚本。

需要进入配置菜单时，在管理员 PowerShell 中显式运行：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/D3-3109/cpu-direct-usb/main/run.ps1))) -Configure
```

配置模式仍需在菜单中选择操作；直接回车跳过。下载前想先审阅，可打开 [run.ps1](run.ps1) 和下面的离线运行方式。

## 离线运行

支持 Windows 10/11 的 Windows PowerShell 5.1。无需安装第三方依赖；请下载本仓库的完整源码目录，保留 `lib` 文件夹。在解压后的目录打开 PowerShell：

```powershell
.\cpudirect.ps1
```

普通权限可扫描。默认不询问修改设置、不自动提权、不联网下载或执行其他脚本，也不更改执行策略。如果系统策略阻止运行，请先检查下载来源、文件属性及本机策略；受管理电脑应遵循组织要求。

导出结构化结果：

```powershell
.\cpudirect.ps1 -Json | Out-File .\usb-report.json -Encoding utf8
```

报告包含设备实例 ID，可能带序列号，分享前可自行脱敏。只扫描当前存在的设备；非正常状态和读取失败会保留在诊断中。拔插设备或换接口后重新运行。

## 如何理解结果

| 显示 | 含义 |
| --- | --- |
| CPU/SoC 控制器（型号推测） | 型号表将该控制器归入 CPU/SoC，仍需核实主板资料 |
| 芯片组控制器（型号推测） | 型号表将该控制器归入芯片组 |
| Thunderbolt / 第三方控制器（上游待核实） | 能识别控制器类型，不能仅凭型号确定 PCIe 上游归属 |
| 控制器归属未知 | 没有足够信息，不自动当作芯片组或直连 |
| N 级 USB 集线器 | 设备到根集线器之间识别出的额外集线器数量；根集线器不计入 |
| 路径不完整 | 父节点缺失、读取失败、出现循环或超过深度上限；不能据此判断直连 |

例如，`CPU/SoC 控制器 → 1 级 USB 集线器 → 输入设备` 会保留 CPU/SoC 归属，不再被标成芯片组。检测到空闲的疑似 CPU/SoC 控制器时，会提示当前输入设备未使用相应路径，不会宣称电脑没有直连 USB。

同型号设备分别显示。一个复合设备的多个输入接口，根据实际物理 USB 父实例合并；无法确定物理父实例时保留接口记录。扫描覆盖 USB HID 及常见 Xbox 设备类，不保证识别所有专有驱动的输入设备。

控制器型号库继承自上游对 Linux `xhci-pci.c` 和 `pci.ids` 的汇总，未逐条重新核验，数据库覆盖范围及平台分类仍可能存在遗漏。系统位置路径用于核对设备树，不直接转换成 CPU/芯片组结论。工具不自动给空闲物理插孔编号，也不测量轮询、USB 传输、DPC 或端到端输入延迟。

## 可选设置与恢复

在管理员 PowerShell 中显式进入配置模式：

```powershell
.\cpudirect.ps1 -Configure
```

菜单说明每项的对象及影响，输入序号执行一项；回车退出。未知的设置不会自动修改。

- **MSI 配置**：只对明确配置为关闭的控制器提供选项。界面读取的是注册表配置，不是当前已分配的中断资源。硬件和驱动支持需要自行确认，修改后需重启才能验证实际效果。
- **控制器选择性挂起**：修改所选控制器的配置值，可能影响其下所有设备；驱动是否使用该值需结合实际环境核实。
- **电源计划选择性挂起**：同时修改所捕获的具体电源计划的插电和电池设置，不局限于一个鼠标。Windows API 分别读取 AC/DC，不解析英文命令输出。工具只保存并验证配置，不自动切换或重新激活计划；修改或恢复后，请在 Windows 电源设置中重新应用对应计划，使配置生效。

关闭选择性挂起可能增加功耗、影响续航。微软默认启用并[建议保留此功能](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-selective-suspend)。这些操作不保证降低输入延迟。

每次操作在写入前保存原状态，默认备份目录为：

```text
%LOCALAPPDATA%\CpuDirectUsb\Backups
```

备份保存失败时不执行设置写入。写入后读回检查；发生部分失败时尝试恢复原状态，并报告恢复是否成功。界面会显示实际备份路径及恢复命令：

```powershell
.\cpudirect.ps1 -Restore 'C:\实际目录\backup.json'
```

恢复需要管理员权限。只接受本机、受支持格式及目标范围内的备份；按备份中的具体电源计划恢复，不把其他活动计划切回旧计划。注册表值原先不存在时会删除新增值；为避免误删其他设置，可保留新建的空注册表键。备份包含设备与机器标识，请妥善保管；只恢复自己生成且信任的文件。如果后续手动调整过同一设置，恢复会以备份原值覆盖它。

## 打包与校验

本次保留仓库原有工作流，自动测试和完整包发布流程待后续补充。**原发布流程只上传单个 `cpudirect.ps1`，缺少本版必须的 `lib` 目录；请使用本分支完整源码，或手动生成完整包。**

在仓库目录执行：

```powershell
.\tools\Package.ps1
```

生成 `dist/cpu-direct-usb-zh.zip`、文件校验清单和压缩包校验清单。输出目录已存在时会拒绝覆盖，可用 `-OutputDirectory` 指定新的目录。解压完整包后可运行：

```powershell
Get-FileHash .\cpudirect.ps1 -Algorithm SHA256
Get-ChildItem .\lib\*.ps1 | Get-FileHash -Algorithm SHA256
```

与同一份完整包的 `checksums.txt` 比较。校验和用于检查文件一致性，不替代可信来源或签名验证。GitHub 自动生成的源码 ZIP 本身不包含这份校验清单。

## 离线测试

```powershell
powershell.exe -NoProfile -NonInteractive -File .\tests\Run.Tests.ps1
```

测试在内存中模拟设备、注册表和电源设置，不需要管理员权限，不枚举真实设备，不修改本机电源计划。覆盖空闲 CPU 控制器、额外 Hub、同型号双设备、复合接口、本地化名称、未知/断链设备，以及设置失败、备份和恢复。本分支暂未配置自动 CI，请在 Windows PowerShell 5.1 下运行上述命令。

离线测试不能替代真实主板拓扑、驱动兼容性和延迟测量。实际设置的生效及收益需在目标电脑上验证。

本地修订内容见 [CHANGELOG.md](CHANGELOG.md)，已执行的验证及边界见 [VALIDATION.md](VALIDATION.md)。

## 来源与许可

- 原项目：[MariusHeier/cpu-direct-usb](https://github.com/MariusHeier/cpu-direct-usb)
- 修订基线：[D3-3109/cpu-direct-usb，87489da](https://github.com/D3-3109/cpu-direct-usb/tree/87489da8e0b17824293f07dc982e47329997f4c0)
- [MIT 许可证](LICENSE)，保留原作者版权声明。
