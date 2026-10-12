@echo off
chcp 65001 >nul
title 奶茶优惠雷达 - 推送到 GitHub
echo.
echo  ============================================
echo   奶茶优惠雷达 iOS - 推送到 GitHub
echo  ============================================
echo.
echo  请先在 https://github.com/new 新建一个仓库
echo  （不要勾选 Add a README file）
echo.
set /p REPO=  粘贴仓库地址（形如 https://github.com/用户名/milktea-radar-ios.git）:
echo.

if "%REPO%"=="" (
  echo  [x] 地址为空，已取消
  pause
  exit /b 1
)

cd /d "%~dp0"

echo  [1/4] 清理旧的 remote ...
git remote remove origin 2>nul

echo  [2/4] 添加 remote ...
git remote add origin "%REPO%"

echo  [3/4] 确保分支名为 main ...
git branch -M main

echo  [4/4] 推送（会弹出登录窗口，密码请用 Personal Access Token）...
git push -u origin main

if errorlevel 1 (
  echo.
  echo  [x] 推送失败。常见原因：
  echo      - 仓库地址填错
  echo      - 认证失败：GitHub 不再支持密码，需用 Personal Access Token
  echo        生成：Settings -^> Developer settings -^> Personal access tokens -^> Tokens ^(classic^)
  echo              勾选 repo 和 workflow
  echo      - 网络问题：可尝试开启代理后重试
) else (
  echo.
  echo  [√] 推送成功！
  echo.
  echo  接下来：
  echo    1. 打开你的仓库页面
  echo    2. 点 Actions 标签
  echo    3. 左侧选 Build iOS App，点 Run workflow
  echo    4. 等 3-5 分钟，在页面底部 Artifacts 下载 ipa
)

echo.
pause
