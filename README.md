# He's Linux Toolbox v2.0

面向个人多节点 VPS 的**一体式 Linux 运维与全量项目一键部署终端控制面板**。

## 一键运行与安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main/init.sh)
```

安装后会自动注册全局命令 `toolbox`（及快捷别名 `he`），后续在服务器任意目录直接运行：

```bash
toolbox                       # 打开交互式终端控制面板
toolbox status                # 一键输出当前服务器实时状态看板
toolbox deploy <repo-name>    # 直接部署指定 GitHub 项目
toolbox update                # 自动更新工具箱到最新版本
```

## 核心功能模块

| 模块 | 覆盖能力 |
| :--- | :--- |
| **实时状态看板** | 面板顶部实时展示主机名、公网 IP、系统内核、BBR 状态、CPU/内存/Swap/磁盘、Docker 容器数与 `/opt` 已安装项目数 |
| **个人项目一键部署** | 按 4 大领域分类接入 22 个核心项目（VPS 运维监控、节点网络面板、AI 网关工具、量化与自动化），自动识别 `[已装]` 状态并匹配专属安装/管理脚本 |
| **已安装项目与容器管理** | 统一巡检 `/opt` 下所有项目、执行 `git pull` 更新、重启 Docker Compose、实时查看容器日志或安全卸载 |
| **常用开源基础服务** | 一键安装 Docker + Compose、Nginx、Caddy（自动 HTTPS）、Node.js 22 + pnpm + PM2、Python3 + uv、1Panel、UFW + Fail2ban |
| **系统调优与急救箱** | 幂等开启 BBR+FQ、灵活配置/移除 Swap（1G/2G/4G）、跨发行版系统与 Docker 清理、时区校准、端口占用与高负载进程排查、网络延迟体检 |
| **安全凭证与镜像源** | **零硬编码密钥**——私有仓库 Token 仅保存在当前服务器本机 `~/.config/he-toolbox/github_token`（权限 `600`），支持一键连通测试与国内镜像自动回退 |

## 私有仓库拉取说明

为了保障账号安全，本公开仓库**绝不内置任何 GitHub Token**。  
如需部署私有仓库，可在面板中进入 **`[5] 凭证与镜像源配置`**，或在终端通过环境变量临时传入：

```bash
export GITHUB_TOKEN="你的只读/repo 权限 PAT"
toolbox deploy sub2api
```
