# Changelog

## 3.1.2-zh2 — 2026-10-29

- 汉化系统托盘右键菜单（TUXEDO Control Center / Aquaris 控制 / 配置 / 托盘自启动 /
  阻止节能 / Fn 锁定 / 显卡 / 选择独显 / 应用按需模式 / 选择核显 / 退出）
- `lib/patch_bundles.py` 新增托盘文案补丁步骤，版本不匹配时给出警告

## 3.1.2-zh1 — 2026-10-29

首个版本。

- 简体中文界面：437 条文案，覆盖仪表板、配置文件、工具、Aquaris、Tomte、摄像头、
  设置、支持、信息等全部页面
- 语言菜单加入“简体中文”，语言按钮支持 English ⇄ 简体中文 切换
- 后台 `availableLanguages` 加入 `zh-CN`，托盘配置名与通知随语言变化
- 纯 Python 解包 `app.asar`，以 `resources/app/` 目录方式加载，原文件备份可还原
- 提供 `install.sh` / `uninstall.sh`、tar.gz 与 deb 安装包
- 支持 `apt remove` 自动还原官方界面
