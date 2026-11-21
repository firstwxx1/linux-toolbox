# He's Linux Toolbox v3.0

个人全量 **32 个 GitHub 项目统一终端部署面板** & **多节点 Linux VPS 运维中枢**。

## 一键运行与安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main/init.sh)
```

安装后会自动注册全局命令 `toolbox`（及快捷别名 `he`）：

```bash
toolbox                       # 打开交互式终端控制面板
toolbox status                # 输出服务器实时遥测看板
toolbox inspect               # 全局巡检 /opt 下所有已装项目的 panel.sh 运行状态
toolbox search <关键词>       # 模糊搜索 32 个项目并秒进其专属面板
toolbox deploy <repo>         # 拉取并启动指定项目的 panel.sh 部署面板
toolbox update                # 自动更新工具箱至最新版
```

## 统一 `panel.sh` 接入协议

已推送代码的业务项目根目录均已配备标准化 `panel.sh` 终端控制面板，统一支持：
- `bash panel.sh` — 交互式项目专属管理菜单（安装 / 启动 / 配置 `.env` / 查日志 / 更新 / 卸载）
- `bash panel.sh status` — 一行状态摘要输出，供 `toolbox inspect` 统一汇总巡检
- `bash panel.sh install` / `start` / `update` / `logs` — 快捷子命令直达

## 核心能力模块

1. **全量 32 项目分类与搜索部署**：按 `运维安全 / 节点网络 / AI 网关 / 量化风控 / 业务应用` 5 大类编排，支持关键词模糊检索
2. **已安装项目巡检 & 容器/Systemd 管理**：全局健康表、私有库自动鉴权批量 `git pull`、Docker 容器重启/查日志、Systemd 快捷控制
3. **开源服务 & 一键 HTTPS 反代向导**：Docker、Nginx、Caddy、Node 22 + pnpm + PM2、Python3 + uv、1Panel、Fail2ban，以及输入「域名 + 本机端口」自动生成 HTTPS 反向代理配置
4. **系统调优、Crontab 与 SSH 安全加固**：幂等 BBR+FQ、1G/2G/4G Swap、跨发行版清理、定时任务管理、SSH 公钥导入与爆破 IP Top10 排查
5. **零硬编码密钥安全机制**：本公开仓库不存储任何 Token，私有库凭证仅保存在服务器本机 `~/.config/he-toolbox/github_token` (`chmod 600`)
