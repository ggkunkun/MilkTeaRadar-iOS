# 如何生成 .ipa（Windows 用户专用）

> 本目录已经是一个**完整的 git 仓库**，CI 配置也已就绪。
> 你只需把它推到自己的 GitHub 账号，云端就会自动编译出 `.ipa`。

---

## 为什么不能在本机直接生成

iOS 的编译产物（Mach-O 二进制）**只能由 Apple 的编译器在 macOS 上产出**。
Windows 上没有 `clang`-for-iOS、没有 iOS SDK、没有代码签名工具 —— 这是 Apple 的平台限制，
任何工具链都绕不过去。

**所以走云端**：GitHub 提供免费的 macOS 运行器，我们借它编译。

---

## 前置条件

只需一样：**一个 GitHub 账号**（免费即可，不需要开发者账号）。

---

## 方式一：网页上传（不用命令行，推荐）

### 1. 新建仓库

1. 打开 https://github.com/new
2. **Repository name** 填 `milktea-radar-ios`
3. 选择 **Public**（私有仓库的 Actions 有免费额度限制，公开仓库完全免费）
4. **不要**勾选 "Add a README file"
5. 点 **Create repository**

### 2. 上传文件

在新仓库页面点 **uploading an existing file**，然后：

把 `奶茶优惠雷达-iOS` 文件夹里的**这些内容**拖进上传区：

```
MilkTeaRadar/               ← 整个文件夹
MilkTeaRadar.xcodeproj/     ← 整个文件夹
.github/                    ← 整个文件夹（含 CI 配置，关键！）
build.sh
project.yml
构建说明.md
如何生成ipa.md
.gitignore
.gitattributes
```

> ⚠️ **注意**：Windows 资源管理器默认隐藏 `.github` 开头（点号开头）的文件夹。
> 在上传页面直接把这个文件夹拖进去即可，或者在「查看 → 显示 → 隐藏的项目」里先打开显示。
> **没有 `.github/workflows/build-ios.yml` 就不会自动构建**，这一步别漏。

然后点 **Commit changes**。

### 3. 触发构建

1. 仓库页面点 **Actions** 标签
2. 左侧选 **Build iOS App**
3. 右侧点 **Run workflow** → 再点绿色的 **Run workflow**
4. 刷新页面，等 3–5 分钟，看到 ✅

### 4. 下载 .ipa

点进那次运行，页面**最下方**有 **Artifacts** 区域，下载：

| 产物 | 说明 | 能否装真机 |
|---|---|---|
| `MilkTeaRadar-unsigned-ipa` | **未签名 ipa** | 需用 Sideloadly 重签（见下） |
| `MilkTeaRadar-simulator` | 模拟器可运行包 | 只能在 Mac 模拟器跑 |

---

## 方式二：命令行推送

如果你习惯命令行，且已配置好凭据：

```bash
cd 奶茶优惠雷达-iOS

# 新建仓库后，复制它给的地址
git remote add origin https://github.com/你的用户名/milktea-radar-ios.git
git branch -M main
git push -u origin main
```

推完自动触发构建（因为 workflow 里配了 `on: push`）。
然后去 Actions 页面下载产物。

> 推送时会要求认证。GitHub 早已不支持密码，需用 **Personal Access Token**：
> GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
> → Generate new token → 勾选 `repo` 和 `workflow` → 复制 token 当密码用。

---

## 拿到未签名 ipa 后怎么装到 iPhone

未签名 ipa 不能直接双击安装，但可以用**你自己的 Apple ID 免费重签**：

| 工具 | 平台 | 说明 |
|---|---|---|
| **Sideloadly** | Windows / Mac | 推荐。连上 iPhone，拖入 ipa，输 Apple ID，点 Start |
| AltStore | Windows / Mac | 需先装 AltServer，支持自动续签 |
| TrollStore | 仅特定 iOS 版本 | 免签名永久安装 |

**Sideloadly 步骤**：

1. 下载安装 https://sideloadly.io/
2. iPhone 用数据线连电脑
3. 把 `MilkTeaRadar-unsigned.ipa` 拖进 Sideloadly
4. Apple ID 填你的（免费账号即可）
5. 点 **Start**，输入 Apple ID 密码
6. 装完后在 iPhone：**设置 → 通用 → VPN与设备管理 → 信任你的证书**

> **免费 Apple ID 的限制**：签名有效期 **7 天**，到期需重新签一次。
> 这是 Apple 对免费账号的限制，与本项目无关。付费开发者账号（$99/年）有效期 1 年。

---

## 想要"直接能装"的正式 ipa？

在仓库 **Settings → Secrets and variables → Actions** 添加 4 个 Secret：

| Secret 名 | 内容 |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | 你的 `.p12` 证书的 base64 |
| `P12_PASSWORD` | 导出 p12 时设的密码 |
| `BUILD_PROVISION_PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `KEYCHAIN_PASSWORD` | 随便填个字符串 |

生成 base64（Windows）：

```cmd
certutil -encode Certificates.p12 cert_b64.txt
```

（去掉首尾的 `-----BEGIN/END CERTIFICATE-----` 行，取中间内容）

配好后再跑一次 workflow，就会多出 `MilkTeaRadar-signed-ipa` —— 这个可以直接装。

---

## 常见问题

**Q：Actions 页面没有 "Build iOS App" 选项**
A：`.github/workflows/build-ios.yml` 没上传成功。检查仓库根目录是否有这个文件。

**Q：构建失败，报找不到 Scheme**
A：`.xcodeproj` 没上传完整。确认 `MilkTeaRadar.xcodeproj/xcshareddata/xcschemes/MilkTeaRadar.xcscheme` 在仓库里。

**Q：模拟器包和 ipa 有什么区别？**
A：模拟器包只能在 Mac 的 iOS 模拟器里运行（不需要签名）；ipa 是给真机用的（需要签名）。

**Q：为什么没有证书也能出 ipa？**
A：因为 workflow 在编译时关掉了签名要求（`CODE_SIGNING_ALLOWED=NO`），
产出的 ipa 里是**未签名**的 App。Sideloadly 这类工具会在安装时用自己的证书重新签。
