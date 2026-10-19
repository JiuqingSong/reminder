# 瘦子提醒

只给自己用的 iPhone 提醒 App：按事件逐条列出，不按日历组织。

- SwiftUI + SwiftData，iOS 18+，全部本地存储，不依赖服务器
- 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，`.xcodeproj` 不进版本库

## 功能与规则

| 项目 | 规则 |
|---|---|
| 常年提醒 | 不设日期。固定显示在列表顶部，可手动排序，不发通知 |
| 待买 | 固定在常年分组第一行，没有物品时也显示，行上显示需要买的件数。点进去是物品列表，每件可以有文字、图片、链接 |
| 普通物品 | 左划标记已买，移到"已买"列表（待买页底部入口）。已买的可以恢复，也可以一键清空（永久删除） |
| 循环物品 | 状态分为"需要买"和"以后检查"。左划只切换状态，不会变成已买。"以后检查"的灰色排在最下面 |
| 批量添加 | 每行一项，添加为普通物品。和待买列表里已有物品重名时，可以选择跳过或重复添加；重名的是"以后检查"的循环物品时，也可以选择把它改回需要买。单个添加时同样检查重名 |
| 购买地点 | 每件物品可以有 0 到多个购买地点，从常用地点里选，也可以当场新建。常用地点在设置或待买页右上角管理：在地图上搜索（一个地点可以加多家分店），或者用纯文字。待买页顶部可以按地点筛选 |
| 到店提醒 | 地图地点可以开启提醒（默认 200 米范围）。到达时如果有需要在那里买的物品，马上通知"以下物品可以在这里购买"，每次到达都会提醒，点通知打开待买页。只需要"使用 App 期间"定位权限。iOS 限制最多同时 64 条待发通知，所以开启提醒的地图位置最多 20 个 |
| Apple Watch | 通知由系统自动转到手表：iPhone 锁屏或黑屏且戴着手表时显示在手表上。在 iPhone 的 Watch App → 通知 → 瘦子提醒 里设置是否在手表显示 |
| 日期 | 可以精确到分钟，也可以只设日期。计算提醒时只看日期部分 |
| 提醒区间 | 每条可单独设置，默认"提前 1 天"。从到期前 N 天起，每天在设定时刻（默认 9:00）汇总发一条通知 |
| 过期 | 显示在"已过期"分组，之后每天继续提醒，直到标记完成 |
| 角标 | 已进入提醒区间且未过期的事项数，不含常年、已过期和待买 |
| 重复 | 每天、每周、每月、每年，可设间隔。完成后生成一条历史记录，原事项顺延到下一次 |
| 地址 | 用 Google 地图打开：装了 App 就打开 App，没装就打开网页版 |
| 链接、电话 | 链接用系统默认浏览器打开，电话号码点击即可拨打 |
| 图片 | 支持拍照和从相册多选。压缩到长边 2048 像素后存在 App 目录，会随 iPhone 备份一起备份 |
| 长按菜单 | 列表中长按某条提醒：完成或恢复、推迟一天、推迟一周、复制文字、删除 |
| 备份 | 在设置里导出成一个 JSON 文件（图片内嵌），可以存到"文件"或 iCloud Drive。恢复时可选"合并"或"替换全部" |
| Siri | 说"用瘦子提醒记一下"（或"瘦子提醒添加待办"等），Siri 问"要提醒什么？"，回答"明天下午2点去洗车"即可。自动识别日期时间，没说日期的进常年提醒 |

### Siri 能识别的时间说法

- 日期：今天、明天、后天、大后天、今晚、明早、3天后、2周后、周五、这周三、下周一、10月20号、2027年1月5日、15号
- 时间：上午10点、下午2点半、晚上8点一刻、14:30。只说"2点"且没说上午下午时，1～5 点按下午算
- 只说时间没说日期：今天还没过就是今天，已过就是明天
- 触发语都要带 App 名，这是 iOS 的限制；直接说"添加待办"会交给系统自带的"提醒事项"
- 第一次装好后，可能要先打开一次 App，Siri 才能认出这些触发语。Siri 的语言要设成中文（普通话）

## 在 Mac 上装到 iPhone（免费 Apple ID）

1. 从 App Store 安装最新版 Xcode。手机是 iOS 27，Xcode 需要 27 或更高。
2. 安装 XcodeGen 并生成工程：
   ```sh
   brew install xcodegen
   xcodegen generate
   open Reminder.xcodeproj
   ```
3. 在 Xcode 中打开 Settings → Accounts，登录你的 Apple ID。
4. 选中 Reminder target，进入 Signing & Capabilities，Team 选择"(你的名字) (Personal Team)"。
   为了避免每次生成工程后都要重选，可以把 Team ID 填进 `project.yml` 的 `DEVELOPMENT_TEAM`。
5. 用数据线连接 iPhone。在手机上打开 **设置 → 隐私与安全性 → 开发者模式**，开启后手机会重启。
6. 在 Xcode 中选择你的 iPhone 作为运行目标，然后点 ▶︎ 运行。
7. 第一次运行时，手机上要信任开发者：**设置 → 通用 → VPN 与设备管理** → 选择你的 Apple ID → 信任。

> 免费账号的签名 **7 天后过期**，过期后 App 无法打开。重新连接手机并在 Xcode 里运行一次即可。
> 这是覆盖安装，**数据不会丢**。注意：不要先删除 App 再重装，删除会清空数据。
> 另外，bundle ID `com.songthin.reminder` 在 Apple 账号下必须唯一。如果签名提示被占用，在 `project.yml` 里换一个。

## GitHub Actions

每次 push 都会在 macOS runner 上生成工程并编译，用来检查代码能否编译通过。
产物是**未签名**的 `Reminder-unsigned.ipa`，在 Actions 页面下载。
这个 ipa 不能直接安装，需要用 Sideloadly 或 AltStore 加上你的 Apple ID 签名后再装，同样 7 天有效。

## 目录

```
Reminder/
  App/        入口、AppDelegate（前台通知）、RootView（回到前台时刷新）、AppModel（共用数据库）
  Intents/    Siri 添加提醒（AddReminderIntent、触发语）
  Models/     Reminder（待买物品也是 Reminder，用 isShopping 区分）、Attachment（SwiftData，兼容 CloudKit）、
              Place / PlaceLocation（购物地点和它的地图位置）、Recurrence
  Services/   BackupService（导出/恢复备份）
              ShoppingActions（待买：已买、循环状态、批量添加、查重）
              PlaceActions、LocationAuthorization（购物地点、定位权限）
              NotificationScheduler（每日汇总通知、到店提醒、角标）
              ReminderActions（完成、恢复、删除，以及保存后重建通知）
              AttachmentStore（图片文件）
              ContentDetector / MapOpener（链接、地址识别）
              SpokenDateParser（从口语里识别日期时间）
              DueFormat、AppSettings
  Views/      列表、详情、编辑、待买（含已买、批量添加）、购物地点（管理、地图搜索、选择）、
              图片浏览、日期筛选、设置
```

## 后续计划

- 桌面小组件
- iCloud 同步（需要付费开发者账号。数据模型已经按 CloudKit 的要求设计，届时只需开启能力）

## 图标

图标是 `Reminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png`，由 `tools/make-icon.ps1` 在 Windows 上生成：

```powershell
powershell -File tools/make-icon.ps1 -Out Reminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```
