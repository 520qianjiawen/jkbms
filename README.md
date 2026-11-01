# 极空 BMS 原生版

使用 SwiftUI 和 CoreBluetooth 编写的 JK-BMS 蓝牙客户端，当前版本 **0.2.2（236）**。

## 功能

- 蓝牙扫描、设备连接、断线重连及协议自动识别。
- 电芯电压、线阻、温度、容量、告警和充放电状态读取。
- 按设备能力开放参数编辑、控制开关和校准，写入后回读确认。
- 显示器报警及两组干接点的触发值、恢复值：随触发源显示 mV / mA / ℃ / %、整数范围及触发/恢复大小关系；写入后读取设备信息确认。
- 设备信息、事件日志、详细历史和 CSV 导出。
- JSON 参数备份及 `.jkcfg` 配置文件导入导出。
- 连接密码、设置密码按设备分别记入本机钥匙串；重连时重新核对，密码变化后提示输入。
- 输入框保留原位置，提供边框、背景及显示/隐藏密码按钮。
- 默认真实设备模式，也可手动开启演示模式。

**当前尚未完成全部机型的硬件验收和全部专属功能。** 已接入 JK 参数表中明确规定的十种数值触发源；关闭、系统报警、远程控制和 MOS 异常不显示数值输入。新版触发源 13（SOC 高于阈值）的数值规则尚未确认，暂不开放阈值编辑。部分机型专属参数和长期后台运行仍有待完善。构建或测试通过不代表所有设备读写已验证。

## 工程结构

- `Sources/JKBMSCore`：协议、设备模型、蓝牙、钥匙串及运行必需的协议表/型号目录。
- `Sources/JKBMSApp`：SwiftUI 界面。
- `Tests`：协议样本、分包校验和密码记忆回归测试。
- `Assets.xcassets`、`PrivacyInfo.xcprivacy`：应用资源与隐私清单。
- `tools`：工程生成及构建脚本。

## 构建与测试

需要安装 Xcode。iOS 最低版本为 17，Swift Package 的 macOS 最低版本为 14。

```sh
swift test
```

构建 iOS 模拟器版本：

```sh
./tools/build_ios.sh
```

真机运行：打开 `JKBMS.xcodeproj`，在 **Signing & Capabilities** 中选择自己的开发团队，选择设备并运行。也可使用命令行：

```sh
python3 tools/generate_xcode_project.py
xcodebuild -project JKBMS.xcodeproj -scheme JKBMS \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/deviceDerivedData \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates build
```

报警阈值按照 [JK 参数说明表](https://www.shop.jkbms.com/jk-bms-dry-contact-wiring-method-diagrams/) 使用原始整数单位。备份中的报警阈值必须带有触发源且与当前设备回读一致；若要更换触发源，请先单独切换并等待回读，再编辑或导入阈值。

新增源文件后可重新运行工程生成脚本。仓库不包含个人开发团队、签名证书、构建产物或本机用户设置。

## 来源与许可

第三方代码和测试样本的归属见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，对应许可证见 `LICENSES/`。
