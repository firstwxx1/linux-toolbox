#!/usr/bin/env bash
# ==============================================================================
# He's Linux Toolbox — 个人多节点 Linux 运维与项目一键部署终端控制面板
# Repository: https://github.com/firstwxx1/linux-toolbox
# ==============================================================================

HE_TOOLBOX_VERSION="2.0.0"
GITHUB_OWNER="firstwxx1"
REPO_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_OWNER}/linux-toolbox/main"
CONFIG_DIR="${HOME}/.config/he-toolbox"
TOKEN_FILE="${CONFIG_DIR}/github_token"
MIRROR_CONF="${CONFIG_DIR}/mirror_mode"
OPT_ROOT="/opt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# 缓存会话级公网 IP，避免每次刷新菜单卡顿
CACHED_PUBLIC_IP=""

# ==============================================================================
# 基础辅助函数
# ==============================================================================

init_config_dir() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[ERR] 该操作需要 root 权限，请使用 sudo -i 或 sudo toolbox 运行。${NC}"
    return 1
  fi
  return 0
}

pause() {
  echo ""
  read -r -p "$(echo -e "${DIM}按回车键继续...${NC}")" _
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v apk >/dev/null 2>&1; then
    echo "apk"
  else
    echo "unknown"
  fi
}

pkg_install() {
  local mgr
  mgr="$(detect_pkg_mgr)"
  case "$mgr" in
    apt)
      apt-get update -y && apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
    apk)
      apk add --no-cache "$@"
      ;;
    *)
      echo -e "${RED}[ERR] 未识别包管理器，请手动安装: $*${NC}"
      return 1
      ;;
  esac
}

ensure_base_cmd() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] 未检测到 ${cmd}，正在自动安装 ${pkg}...${NC}"
    pkg_install "$pkg"
  fi
}

get_mirror_mode() {
  if [ -f "$MIRROR_CONF" ]; then
    cat "$MIRROR_CONF"
  else
    echo "auto"
  fi
}

get_github_token() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    printf '%s' "$GITHUB_TOKEN"
  elif [ -f "$TOKEN_FILE" ]; then
    tr -d ' \r\n' < "$TOKEN_FILE"
  else
    printf ''
  fi
}

has_github_token() {
  local tok
  tok="$(get_github_token)"
  [ -n "$tok" ]
}

prompt_token_if_missing() {
  local repo_label="$1"
  if has_github_token; then
    return 0
  fi
  echo -e "${YELLOW}[AUTH] 「${repo_label}」是私有仓库，当前机器尚未配置 GitHub Token。${NC}"
  echo -e "${DIM}提示：Token 仅加密权限保存于本机 ${TOKEN_FILE} (chmod 600)，不会写入仓库。${NC}"
  read -r -s -p "请输入 GitHub PAT (留空取消): " input_tok
  echo ""
  if [ -z "$input_tok" ]; then
    echo -e "${RED}[CANCEL] 未输入 Token，已取消操作。${NC}"
    return 1
  fi
  init_config_dir
  printf '%s' "$input_tok" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo -e "${GREEN}[OK] Token 已安全保存至本机。${NC}"
  return 0
}

# 构建 Git 鉴权 header（避免把 Token 写死进 .git/config）
git_with_auth() {
  local is_private="$1"
  shift
  if [ "$is_private" = "private" ]; then
    local tok b64
    tok="$(get_github_token)"
    if [ -z "$tok" ]; then
      echo -e "${RED}[ERR] 缺少 GitHub Token，无法拉取私有仓库。${NC}"
      return 1
    fi
    b64="$(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
    git -c "http.extraheader=AUTHORIZATION: basic ${b64}" "$@"
  else
    git "$@"
  fi
}

resolve_github_clone_url() {
  local full_repo="$1"
  local is_private="$2"
  local base_url="https://github.com/${full_repo}.git"

  # 私有仓库一律直连 GitHub，禁止经过第三方镜像泄露凭据
  if [ "$is_private" = "private" ]; then
    echo "$base_url"
    return
  fi

  local mode
  mode="$(get_mirror_mode)"
  if [ "$mode" = "direct" ]; then
    echo "$base_url"
    return
  fi
  if [ "$mode" = "mirror" ]; then
    echo "https://ghfast.top/${base_url}"
    return
  fi

  # auto 模式：快速探测 GitHub 直连
  if curl -fsI --connect-timeout 3 --max-time 5 "https://github.com" >/dev/null 2>&1; then
    echo "$base_url"
  else
    echo "https://ghfast.top/${base_url}"
  fi
}

# ==============================================================================
# 实时系统遥测看板
# ==============================================================================

get_public_ip() {
  if [ -n "$CACHED_PUBLIC_IP" ]; then
    echo "$CACHED_PUBLIC_IP"
    return
  fi
  local ip=""
  ip="$(curl -4 -fsS --connect-timeout 2 --max-time 3 https://api.ipify.org 2>/dev/null || curl -4 -fsS --connect-timeout 2 --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  CACHED_PUBLIC_IP="${ip:-未知}"
  echo "$CACHED_PUBLIC_IP"
}

render_dashboard() {
  local host os kernel ip bbr cpu_cores load mem_info swap_info disk_info docker_stat opt_count tok_stat mirror_mode

  host="$(hostname 2>/dev/null || echo unknown)"
  os="$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' | cut -c1-34)"
  [ -z "$os" ] && os="$(uname -s)"
  kernel="$(uname -r | cut -c1-24)"
  ip="$(get_public_ip)"

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi bbr; then
    bbr="${GREEN}BBR ON${NC}"
  else
    bbr="${YELLOW}BBR OFF${NC}"
  fi

  cpu_cores="$(nproc 2>/dev/null || echo '?')"
  load="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || uptime | awk -F'load average:' '{print $2}' | xargs)"
  mem_info="$(free -h 2>/dev/null | awk 'NR==2{print $3" / "$2}')"
  swap_info="$(free -h 2>/dev/null | awk 'NR==3{print $3" / "$2}')"
  [ -z "$swap_info" ] && swap_info="未配置"
  disk_info="$(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"}')"

  if command -v docker >/dev/null 2>&1; then
    local running total
    running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    total="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
    docker_stat="${GREEN}运行中${NC} (${running}/${total} 容器)"
  else
    docker_stat="${DIM}未安装${NC}"
  fi

  opt_count="$(find "$OPT_ROOT" -maxdepth 2 -name ".git" -type d 2>/dev/null | wc -l | tr -d ' ')"

  if has_github_token; then
    tok_stat="${GREEN}已配置${NC}"
  else
    tok_stat="${YELLOW}未配置${NC}"
  fi
  mirror_mode="$(get_mirror_mode)"

  echo -e "${CYAN}┌──────────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│${NC}  ${BOLD}${WHITE}He's Linux Toolbox${NC} ${CYAN}v${HE_TOOLBOX_VERSION}${NC}   ${DIM}个人多节点运维 & 一键部署终端控制面板${NC}   ${CYAN}│${NC}"
  echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────┤${NC}"
  printf "${CYAN}│${NC}  主机: ${WHITE}%-22s${NC}  公网IP: ${CYAN}%-22s${NC} ${CYAN}│${NC}\n" "${host:0:22}" "${ip:0:22}"
  printf "${CYAN}│${NC}  系统: %-28s  内核: %-18s ${CYAN}│${NC}\n" "${os:0:28}" "${kernel:0:18}"
  echo -e "${CYAN}│${NC}  负载: ${WHITE}${cpu_cores}C${NC} (${load})   网络: ${bbr}   镜像: ${CYAN}${mirror_mode}${NC}"
  echo -e "${CYAN}│${NC}  内存: ${WHITE}${mem_info:-N/A}${NC}   Swap: ${swap_info}   磁盘: ${WHITE}${disk_info:-N/A}${NC}"
  echo -e "${CYAN}│${NC}  Docker: ${docker_stat}   /opt 项目: ${CYAN}${opt_count}${NC} 个   私有Token: ${tok_stat}"
  echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────┘${NC}"
}

# ==============================================================================
# 智能项目部署引擎
# 参数: repo_name | visibility (public/private) | custom_entry (可选) | description
# ==============================================================================

is_installed_badge() {
  local repo="$1"
  if [ -d "${OPT_ROOT}/${repo}" ]; then
    echo -e "${GREEN}[已装]${NC}"
  else
    echo -e "${DIM}[未装]${NC}"
  fi
}

deploy_project() {
  local repo_spec="$1"
  local visibility="${2:-public}"
  local custom_entry="${3:-}"
  local full_repo repo_name target_dir

  if [[ "$repo_spec" == */* ]]; then
    full_repo="$repo_spec"
    repo_name="${repo_spec##*/}"
  else
    full_repo="${GITHUB_OWNER}/${repo_spec}"
    repo_name="$repo_spec"
  fi

  target_dir="${OPT_ROOT}/${repo_name}"

  echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}准备部署项目:${NC} ${WHITE}${full_repo}${NC}  (${visibility})"
  echo -e "  ${BOLD}目标路径:${NC}     ${target_dir}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

  # 特殊快捷分支：1Panel 官方安装器
  if [ "$repo_name" = "1Panel" ]; then
    echo -e "  1. 运行 1Panel 官方 v2 一键安装脚本 (推荐)"
    echo -e "  2. 克隆源码仓 ${full_repo} 到 ${target_dir}"
    echo -e "  0. 返回"
    read -r -p "请选择 [0-2]: " p_choice
    case "$p_choice" in
      1)
        bash -c "$(curl -sSL https://resource.1panel.pro/v2/quick_start.sh)"
        pause
        return
        ;;
      2) ;;
      *) return ;;
    esac
  fi

  ensure_base_cmd git git
  ensure_base_cmd curl curl

  if [ "$visibility" = "private" ]; then
    prompt_token_if_missing "$full_repo" || { pause; return 1; }
  fi

  # 若已安装，提供快捷管理选项
  if [ -d "$target_dir" ]; then
    echo -e "${GREEN}[INFO] 目录 ${target_dir} 已存在。${NC}"
    echo -e "  1. 拉取最新代码并运行安装/管理面板"
    echo -e "  2. 仅执行 git pull 更新代码"
    echo -e "  3. 仅启动安装/管理面板（不拉取更新）"
    echo -e "  4. 查看 README.md 前 45 行说明"
    echo -e "  5. ${RED}卸载并删除目录 ${target_dir}${NC}"
    echo -e "  0. 返回"
    read -r -p "请选择操作 [0-5]: " ex_choice
    case "$ex_choice" in
      1)
        echo -e "${YELLOW}[INFO] 正在更新代码...${NC}"
        (cd "$target_dir" && git_with_auth "$visibility" pull --ff-only || git_with_auth "$visibility" pull)
        run_project_entrypoint "$target_dir" "$custom_entry"
        ;;
      2)
        (cd "$target_dir" && git_with_auth "$visibility" pull --ff-only || git_with_auth "$visibility" pull)
        echo -e "${GREEN}[OK] 代码更新完成。${NC}"
        ;;
      3)
        run_project_entrypoint "$target_dir" "$custom_entry"
        ;;
      4)
        if [ -f "${target_dir}/README.md" ]; then
          head -n 45 "${target_dir}/README.md"
        else
          echo -e "${YELLOW}该目录暂无 README.md${NC}"
        fi
        ;;
      5)
        read -r -p "$(echo -e "${RED}确认停止容器并删除 ${target_dir}？输入 YES 确认: ${NC}")" confirm_del
        if [ "$confirm_del" = "YES" ]; then
          if [ -f "${target_dir}/docker-compose.yml" ] && command -v docker >/dev/null 2>&1; then
            (cd "$target_dir" && docker compose down 2>/dev/null || true)
          fi
          rm -rf "$target_dir"
          echo -e "${GREEN}[OK] 已卸载并清理 ${target_dir}${NC}"
        else
          echo -e "${YELLOW}已取消删除。${NC}"
        fi
        ;;
      *) return ;;
    esac
    pause
    return
  fi

  # 首次克隆
  local clone_url
  clone_url="$(resolve_github_clone_url "$full_repo" "$visibility")"
  echo -e "${YELLOW}[INFO] 正在克隆 ${clone_url} -> ${target_dir} ...${NC}"
  if ! git_with_auth "$visibility" clone --depth=1 "$clone_url" "$target_dir"; then
    echo -e "${RED}[ERR] 克隆失败！请检查网络连通性、仓库名或 GitHub Token 权限。${NC}"
    pause
    return 1
  fi

  echo -e "${GREEN}[OK] 仓库拉取完成: ${target_dir}${NC}"
  run_project_entrypoint "$target_dir" "$custom_entry"
  pause
}

run_project_entrypoint() {
  local dir="$1"
  local custom_entry="${2:-}"

  cd "$dir" || return 1

  # 1. 优先执行项目指定的专属入口
  if [ -n "$custom_entry" ] && [ -f "${dir}/${custom_entry}" ]; then
    echo -e "${CYAN}[RUN] 检测到专属入口 ${custom_entry}，准备执行...${NC}"
    if [[ "$custom_entry" == *.sh ]]; then
      chmod +x "$custom_entry"
      bash "$custom_entry"
      return
    elif [[ "$custom_entry" == *.py ]]; then
      ensure_python_env "$dir"
      python3 "$custom_entry"
      return
    fi
  fi

  # 2. 自动嗅探常见部署与控制面板脚本
  local sh_candidates=(
    "quick-install.sh"
    "workbuddy-deploy.sh"
    "quickstart/install.sh"
    "deploy/install_bybit_demo.sh"
    "scripts/deploy.sh"
    "main_menu.sh"
    "menu.sh"
    "start.sh"
    "install.sh"
    "deploy.sh"
    "bootstrap.sh"
  )
  for s in "${sh_candidates[@]}"; do
    if [ -f "${dir}/${s}" ]; then
      echo -e "${CYAN}[RUN] 嗅探到脚本 ${s}，准备启动...${NC}"
      chmod +x "${dir}/${s}"
      bash "${dir}/${s}"
      return
    fi
  done

  # 3. 嗅探 Python 交互菜单
  local py_candidates=("terminal_menu.py" "config_menu.py" "install.py" "web_panel.py")
  for p in "${py_candidates[@]}"; do
    if [ -f "${dir}/${p}" ]; then
      echo -e "${CYAN}[RUN] 嗅探到 Python 入口 ${p}，准备环境并启动...${NC}"
      ensure_python_env "$dir"
      python3 "${dir}/${p}"
      return
    fi
  done

  # 4. Docker Compose 项目
  if [ -f "${dir}/docker-compose.yml" ] || [ -f "${dir}/compose.yml" ]; then
    echo -e "${YELLOW}[INFO] 检测到 Docker Compose 配置。${NC}"
    read -r -p "是否立即执行 docker compose up -d？[y/N]: " run_dc
    if [[ "$run_dc" =~ ^[Yy]$ ]]; then
      ensure_docker_ready || return 1
      docker compose up -d
      docker compose ps
    fi
    return
  fi

  # 5. 纯源码/Node/Python 提示
  echo -e "${YELLOW}[HINT] 未检测到自动安装脚本，目录文件一览：${NC}"
  ls -la "$dir" | head -n 20
  if [ -f "${dir}/README.md" ]; then
    echo -e "${CYAN}--- README.md 摘要 ---${NC}"
    head -n 25 "${dir}/README.md"
  fi
}

ensure_python_env() {
  local dir="$1"
  ensure_base_cmd python3 python3
  if [ -f "${dir}/requirements.txt" ]; then
    if ! command -v pip3 >/dev/null 2>&1; then
      pkg_install python3-pip || true
    fi
    echo -e "${YELLOW}[INFO] 安装 requirements.txt 依赖...${NC}"
    pip3 install -r "${dir}/requirements.txt" --break-system-packages 2>/dev/null || pip3 install -r "${dir}/requirements.txt" || true
  fi
}

ensure_docker_ready() {
  if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] 未安装 Docker，正在自动安装...${NC}"
    svc_install_docker "nopause"
  fi
}

# ==============================================================================
# 模块 1: 个人 GitHub 项目分类部署菜单
# ==============================================================================

menu_projects() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [1] 个人 GitHub 项目一键部署中心${NC}   ${DIM}(🔒 = 私有仓库，需配置本机 Token)${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}A. VPS 运维与安全监控${NC}"
    echo -e "     1) vps-gdrive-backup        $(is_installed_badge vps-gdrive-backup)  Google Drive 5TB 多节点备份面板"
    echo -e "     2) vps-security-monitor     $(is_installed_badge vps-security-monitor)  Telegram 安全巡检与告警守卫"
    echo -e "     3) ct8-auto-renew           $(is_installed_badge ct8-auto-renew)  CT8 免费主机自动续期脚本"
    echo -e "     4) 1Panel                   $(is_installed_badge 1Panel)  1Panel 开源 Linux 运维面板"
    echo ""
    echo -e "  ${YELLOW}B. 节点管理与网络代理${NC}"
    echo -e "     5) nodehub                  $(is_installed_badge nodehub)  多 VPS 代理节点主控管理面板"
    echo -e "     6) node-deploy              $(is_installed_badge node-deploy)  VLESS-Reality + Hy2 + SOCKS5 一键部署"
    echo -e "     7) nodepanel-installer      $(is_installed_badge nodepanel-installer)  自建代理节点管理面板"
    echo -e "     8) hysteria2-installer      $(is_installed_badge hysteria2-installer)  Hysteria 2 生产级一键部署脚本"
    echo -e "     9) agent2api-egress         $(is_installed_badge agent2api-egress)  mihomo 逐账号订阅出口与看门狗"
    echo -e "    10) substore-platform 🔒     $(is_installed_badge substore-platform)  SubStore 订阅商城 Monorepo"
    echo -e "    11) airport-stack 🔒         $(is_installed_badge airport-stack)  Xboard + NodeHub 整合同步桥"
    echo ""
    echo -e "  ${YELLOW}C. AI 网关、机器人与创意工具${NC}"
    echo -e "    12) WorkBuddy-Proxy          $(is_installed_badge WorkBuddy-Proxy)  WorkBuddy 网关 + 管理面板整合版"
    echo -e "    13) WorkBuddy-Daily 🔒       $(is_installed_badge WorkBuddy-Daily)  WorkBuddy 成长中心自动签到"
    echo -e "    14) claude-telegram-bot 🔒   $(is_installed_badge claude-telegram-bot)  Claude Code CLI Telegram 机器人"
    echo -e "    15) sub2api 🔒               $(is_installed_badge sub2api)  Sub2API 定制网关与安装面板"
    echo -e "    16) muse-video-installer     $(is_installed_badge muse-video-installer)  Muse Video 工作台一键安装器"
    echo -e "    17) Alle-gmail               $(is_installed_badge Alle-gmail)  AI 邮件聚合客户端"
    echo ""
    echo -e "  ${YELLOW}D. 量化风控与自动化业务${NC}"
    echo -e "    18) bybit-demo-auto-protection $(is_installed_badge bybit-demo-auto-protection) Bybit V5 模拟盘自动风控系统"
    echo -e "    19) okx-demo-auto-protection   $(is_installed_badge okx-demo-auto-protection) OKX 模拟盘 AI 止盈止损推送"
    echo -e "    20) okx-demo-risk-reporter 🔒  $(is_installed_badge okx-demo-risk-reporter) OKX 模拟盘新闻与风控播报"
    echo -e "    21) crypto-bot-vps 🔒          $(is_installed_badge crypto-bot-vps) Freqtrade 本地化 Flask 运维面板"
    echo -e "    22) ecommerce-automation 🔒    $(is_installed_badge ecommerce-automation) 多平台电商自动化与 RPA 引擎"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "     0) 返回主菜单"
    echo ""
    read -r -p "请输入项目编号 [0-22]: " p_idx
    case "$p_idx" in
      1)  deploy_project "vps-gdrive-backup" "public" "quick-install.sh" ;;
      2)  deploy_project "vps-security-monitor" "public" "install.sh" ;;
      3)  deploy_project "ct8-auto-renew" "public" "renew.py" ;;
      4)  deploy_project "1Panel" "public" "" ;;
      5)  deploy_project "nodehub" "public" "" ;;
      6)  deploy_project "node-deploy" "public" "deploy.sh" ;;
      7)  deploy_project "nodepanel-installer" "public" "install.sh" ;;
      8)  deploy_project "hysteria2-installer" "public" "install.sh" ;;
      9)  deploy_project "agent2api-egress" "public" "install.sh" ;;
      10) deploy_project "substore-platform" "private" "" ;;
      11) deploy_project "airport-stack" "private" "" ;;
      12) deploy_project "WorkBuddy-Proxy" "public" "workbuddy-deploy.sh" ;;
      13) deploy_project "WorkBuddy-Daily" "private" "workbuddy_daily.py" ;;
      14) deploy_project "claude-telegram-bot" "private" "bot.py" ;;
      15) deploy_project "sub2api" "private" "quickstart/install.sh" ;;
      16) deploy_project "muse-video-installer" "public" "install.sh" ;;
      17) deploy_project "Alle-gmail" "public" "" ;;
      18) deploy_project "bybit-demo-auto-protection" "public" "deploy/install_bybit_demo.sh" ;;
      19) deploy_project "okx-demo-auto-protection" "public" "" ;;
      20) deploy_project "okx-demo-risk-reporter" "private" "config_menu.py" ;;
      21) deploy_project "crypto-bot-vps" "private" "main_menu.sh" ;;
      22) deploy_project "ecommerce-automation" "private" "deploy.sh" ;;
      0)  return ;;
      *)  echo -e "${RED}无效编号${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 2: 已安装项目 & Docker 容器管理中心
# ==============================================================================

menu_manage_installed() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [2] 已安装项目与容器管理中心${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"

    echo -e "${YELLOW}▶ /opt 目录下的 Git 项目:${NC}"
    local repos=()
    while IFS= read -r gitdir; do
      [ -n "$gitdir" ] && repos+=("$(dirname "$gitdir")")
    done < <(find "$OPT_ROOT" -maxdepth 2 -name ".git" -type d 2>/dev/null | sort)

    if [ "${#repos[@]}" -eq 0 ]; then
      echo -e "  ${DIM}(暂无通过工具箱安装在 /opt 下的 Git 项目)${NC}"
    else
      local i=1
      for d in "${repos[@]}"; do
        local name branch last_commit
        name="$(basename "$d")"
        branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
        last_commit="$(git -C "$d" log -1 --format='%cd (%s)' --date=short 2>/dev/null | cut -c1-44)"
        printf "  ${CYAN}%2d)${NC} %-26s ${DIM}[%s] %s${NC}\n" "$i" "$name" "$branch" "$last_commit"
        i=$((i + 1))
      done
    fi

    echo ""
    echo -e "${YELLOW}▶ Docker 容器状态:${NC}"
    if command -v docker >/dev/null 2>&1; then
      docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -n 15 | sed 's/^/  /'
    else
      echo -e "  ${DIM}(Docker 未安装)${NC}"
    fi

    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  a) 批量更新 /opt 下全部 Git 公开项目"
    echo -e "  l) 查看指定 Docker 容器最近 80 行日志"
    echo -e "  r) 重启指定 Docker 容器"
    echo -e "  p) 查看当前本机监听端口 (ss -tulpn)"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "输入序号管理对应 /opt 项目，或输入 [a/l/r/p/0]: " m_opt
    case "$m_opt" in
      0) return ;;
      a|A)
        for d in "${repos[@]}"; do
          echo -e "${CYAN}>>> 更新 $(basename "$d") ...${NC}"
          (cd "$d" && git pull --ff-only 2>/dev/null || echo -e "${YELLOW}  (跳过：可能需要私有 Token 或存在本地改动)${NC}")
        done
        pause
        ;;
      l|L)
        read -r -p "请输入容器名称: " cname
        [ -n "$cname" ] && docker logs --tail 80 "$cname"
        pause
        ;;
      r|R)
        read -r -p "请输入要重启的容器名称: " cname
        [ -n "$cname" ] && docker restart "$cname" && echo -e "${GREEN}[OK] 容器 ${cname} 已重启${NC}"
        pause
        ;;
      p|P)
        echo -e "${CYAN}--- 监听端口一览 ---${NC}"
        ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null
        pause
        ;;
      *)
        if [[ "$m_opt" =~ ^[0-9]+$ ]] && [ "$m_opt" -ge 1 ] && [ "$m_opt" -le "${#repos[@]}" ]; then
          local sel_dir="${repos[$((m_opt - 1))]}"
          local sel_name
          sel_name="$(basename "$sel_dir")"
          deploy_project "$sel_name" "public" ""
        else
          echo -e "${RED}输入无效${NC}"; sleep 1
        fi
        ;;
    esac
  done
}

# ==============================================================================
# 模块 3: 常用开源基础服务一键安装
# ==============================================================================

svc_install_docker() {
  local mode="${1:-pause}"
  echo -e "${YELLOW}[INFO] 开始安装 Docker & Docker Compose...${NC}"
  if curl -fsI --connect-timeout 3 https://get.docker.com >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | bash
  else
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
  fi
  systemctl enable --now docker 2>/dev/null || true
  docker --version && docker compose version
  echo -e "${GREEN}[OK] Docker 安装完成！${NC}"
  [ "$mode" = "pause" ] && pause
}

svc_install_nginx() {
  echo -e "${YELLOW}[INFO] 正在安装 Nginx...${NC}"
  pkg_install nginx
  systemctl enable --now nginx 2>/dev/null || true
  nginx -v
  echo -e "${GREEN}[OK] Nginx 已启动！${NC}"
  pause
}

svc_install_caddy() {
  echo -e "${YELLOW}[INFO] 正在安装 Caddy (自动 HTTPS 反代服务器)...${NC}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  if [ "$mgr" = "apt" ]; then
    apt-get update -y
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -y && apt-get install -y caddy
  else
    pkg_install caddy || echo -e "${YELLOW}请参考 https://caddyserver.com/docs/install 完成安装${NC}"
  fi
  systemctl enable --now caddy 2>/dev/null || true
  caddy version 2>/dev/null || true
  echo -e "${GREEN}[OK] Caddy 安装完成！配置文件位于 /etc/caddy/Caddyfile${NC}"
  pause
}

svc_install_nodejs() {
  echo -e "${YELLOW}[INFO] 正在安装 Node.js 22 LTS + pnpm + PM2...${NC}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  if [ "$mgr" = "apt" ]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  elif [ "$mgr" = "dnf" ] || [ "$mgr" = "yum" ]; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
    "$mgr" install -y nodejs
  fi
  npm install -g pnpm pm2
  echo -e "${GREEN}[OK] Node $(node -v) / pnpm $(pnpm -v) / pm2 $(pm2 -v) 安装完成！${NC}"
  pause
}

svc_install_python_uv() {
  echo -e "${YELLOW}[INFO] 正在安装 Python3 + pip + venv + uv...${NC}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  if [ "$mgr" = "apt" ]; then
    pkg_install python3 python3-pip python3-venv
  else
    pkg_install python3 python3-pip
  fi
  curl -LsSf https://astral.sh/uv/install.sh | sh || true
  echo -e "${GREEN}[OK] Python 环境就绪: $(python3 --version)${NC}"
  pause
}

svc_install_security() {
  echo -e "${YELLOW}[INFO] 安装 UFW 防火墙与 Fail2ban (默认放行 SSH 22 端口防失联)...${NC}"
  pkg_install ufw fail2ban
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
  systemctl enable --now fail2ban 2>/dev/null || true
  echo -e "${GREEN}[OK] Fail2ban 已启用；UFW 已放行 22/80/443（如需启用防火墙请手动执行: ufw enable）${NC}"
  pause
}

menu_services() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [3] 常用开源基础服务一键安装${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 安装 Docker + Docker Compose v2"
    echo -e "  2) 安装 Nginx Web 服务器"
    echo -e "  3) 安装 Caddy（自动签发 HTTPS 证书的反代神器）"
    echo -e "  4) 安装 Node.js 22 LTS + pnpm + PM2"
    echo -e "  5) 安装 Python 3 + pip + venv + uv"
    echo -e "  6) 安装 1Panel v2 开源运维面板"
    echo -e "  7) 安装 Fail2ban + UFW 基础安全加固"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-7]: " s_opt
    case "$s_opt" in
      1) svc_install_docker ;;
      2) svc_install_nginx ;;
      3) svc_install_caddy ;;
      4) svc_install_nodejs ;;
      5) svc_install_python_uv ;;
      6) bash -c "$(curl -sSL https://resource.1panel.pro/v2/quick_start.sh)"; pause ;;
      7) svc_install_security ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 4: 系统调优与运维急救箱
# ==============================================================================

ops_enable_bbr() {
  echo -e "${YELLOW}[INFO] 检查并开启 TCP BBR + FQ 拥塞控制...${NC}"
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi bbr; then
    echo -e "${GREEN}[OK] BBR 已经处于开启状态！${NC}"
    sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
    pause
    return
  fi
  grep -q '^net.core.default_qdisc=fq' /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  grep -q '^net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p
  echo -e "${GREEN}[OK] BBR 配置已生效！${NC}"
  pause
}

ops_manage_swap() {
  echo -e "${CYAN}当前内存与 Swap:${NC}"
  free -h
  echo ""
  echo -e "  1) 创建/重建 1G Swap"
  echo -e "  2) 创建/重建 2G Swap (推荐)"
  echo -e "  3) 创建/重建 4G Swap"
  echo -e "  4) 关闭并移除 /swapfile"
  echo -e "  0) 返回"
  read -r -p "请选择 [0-4]: " sw
  local size_mb=0
  case "$sw" in
    1) size_mb=1024 ;;
    2) size_mb=2048 ;;
    3) size_mb=4096 ;;
    4)
      swapoff /swapfile 2>/dev/null || true
      rm -f /swapfile
      sed -i '\|/swapfile|d' /etc/fstab
      echo -e "${GREEN}[OK] 已关闭并移除 /swapfile${NC}"
      pause
      return
      ;;
    *) return ;;
  esac

  swapoff /swapfile 2>/dev/null || true
  rm -f /swapfile
  echo -e "${YELLOW}[INFO] 正在创建 ${size_mb}MB Swap 文件...${NC}"
  fallocate -l "${size_mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  free -h
  echo -e "${GREEN}[OK] Swap 配置完成！${NC}"
  pause
}

ops_clean_system() {
  echo -e "${YELLOW}[INFO] 开始执行跨发行版系统清理...${NC}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  case "$mgr" in
    apt) apt-get autoremove -y && apt-get autoclean -y && apt-get clean ;;
    dnf) dnf autoremove -y && dnf clean all ;;
    yum) yum clean all ;;
  esac
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-time=3d
  fi
  if command -v docker >/dev/null 2>&1; then
    read -r -p "是否同时清理未使用的 Docker 悬空镜像与构建缓存？[y/N]: " prune_dk
    if [[ "$prune_dk" =~ ^[Yy]$ ]]; then
      docker system prune -f
    fi
  fi
  echo -e "${GREEN}[OK] 清理完成！当前磁盘使用：${NC}"
  df -h /
  pause
}

ops_init_vps() {
  echo -e "${YELLOW}[INFO] 校准时区至 Asia/Shanghai 并安装基础运维工具包...${NC}"
  timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  pkg_install curl wget git vim htop jq unzip tar ca-certificates lsof
  echo -e "${GREEN}[OK] 初始化完成！当前系统时间: $(date)${NC}"
  pause
}

ops_inspect_perf() {
  echo -e "${CYAN}=== Top 10 CPU/内存 占用进程 ===${NC}"
  ps aux --sort=-%mem | head -n 11
  echo ""
  echo -e "${CYAN}=== 正在监听的 TCP/UDP 端口 ===${NC}"
  ss -tulpn 2>/dev/null | head -n 25 || netstat -tulpn 2>/dev/null | head -n 25
  pause
}

ops_network_diag() {
  echo -e "${CYAN}=== 网络出口与节点连通性体检 ===${NC}"
  echo -e "  IPv4 出口: $(curl -4 -fsS --max-time 4 https://ipinfo.io/json 2>/dev/null | tr '\n' ' ' | cut -c1-120 || get_public_ip)"
  echo -e "  IPv6 出口: $(curl -6 -fsS --max-time 3 https://api64.ipify.org 2>/dev/null || echo '无 IPv6')"
  echo ""
  for target in "github.com" "api.github.com" "1.1.1.1" "223.5.5.5"; do
    local ms
    ms="$(ping -c 2 -W 2 "$target" 2>/dev/null | awk -F'/' 'END{if($5) print $5" ms"; else print "超时"}')"
    printf "  %-18s -> %s\n" "$target" "$ms"
  done
  pause
}

menu_ops() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [4] 系统调优与运维急救箱${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 开启 TCP BBR + FQ 网络加速（幂等防重复）"
    echo -e "  2) 智能管理 Swap 虚拟内存（1G / 2G / 4G / 移除）"
    echo -e "  3) 清理系统缓存、3天前日志与 Docker 悬空镜像"
    echo -e "  4) 新机初始化（上海时区 + curl/git/vim/htop/jq/lsof）"
    echo -e "  5) 进程高负载与端口占用速查（Top10 + ss -tulpn）"
    echo -e "  6) 网络出口归属地与 GitHub/DNS 延迟体检"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-6]: " o_opt
    case "$o_opt" in
      1) ops_enable_bbr ;;
      2) ops_manage_swap ;;
      3) ops_clean_system ;;
      4) ops_init_vps ;;
      5) ops_inspect_perf ;;
      6) ops_network_diag ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 5: 凭证、镜像源与面板自更新
# ==============================================================================

self_update() {
  echo -e "${YELLOW}[INFO] 正在从 GitHub 更新 He's Linux Toolbox...${NC}"
  bash <(curl -fsSL "${REPO_RAW_BASE}/init.sh" || curl -fsSL "https://ghfast.top/${REPO_RAW_BASE}/init.sh") status
  echo -e "${GREEN}[OK] 工具箱已更新到最新版本！${NC}"
}

menu_settings() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [5] 安全凭证、镜像源与工具箱自身管理${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 配置 / 更新本机 GitHub Token（安全保存至 ~/.config，chmod 600）"
    echo -e "  2) 测试当前 GitHub Token 有效性"
    echo -e "  3) 清除本机保存的 GitHub Token"
    echo -e "  4) 切换 GitHub 访问模式（当前: ${CYAN}$(get_mirror_mode)${NC}）"
    echo -e "  5) 立即更新本终端控制面板至最新版"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-5]: " c_opt
    case "$c_opt" in
      1)
        read -r -s -p "请输入新的 GitHub PAT: " new_tok
        echo ""
        if [ -n "$new_tok" ]; then
          init_config_dir
          printf '%s' "$new_tok" > "$TOKEN_FILE"
          chmod 600 "$TOKEN_FILE"
          echo -e "${GREEN}[OK] Token 已安全保存。${NC}"
        fi
        pause
        ;;
      2)
        local tok
        tok="$(get_github_token)"
        if [ -z "$tok" ]; then
          echo -e "${YELLOW}当前未配置 Token。${NC}"
        else
          local login
          login="$(curl -fsS -H "Authorization: Bearer ${tok}" https://api.github.com/user 2>/dev/null | grep -m1 '"login"' | cut -d'"' -f4)"
          if [ -n "$login" ]; then
            echo -e "${GREEN}[OK] Token 有效！当前认证账号: ${login}${NC}"
          else
            echo -e "${RED}[FAIL] Token 无效或网络无法连通 api.github.com${NC}"
          fi
        fi
        pause
        ;;
      3)
        rm -f "$TOKEN_FILE"
        echo -e "${GREEN}[OK] 已清除本机 GitHub Token。${NC}"
        pause
        ;;
      4)
        init_config_dir
        echo -e "  1) auto   — 自动测速（默认推荐）"
        echo -e "  2) direct — 始终直连 GitHub"
        echo -e "  3) mirror — 公开仓走国内加速镜像"
        read -r -p "选择模式 [1-3]: " mm
        case "$mm" in
          1) echo "auto" > "$MIRROR_CONF" ;;
          2) echo "direct" > "$MIRROR_CONF" ;;
          3) echo "mirror" > "$MIRROR_CONF" ;;
        esac
        echo -e "${GREEN}[OK] 已切换为: $(get_mirror_mode)${NC}"
        pause
        ;;
      5)
        self_update
        pause
        ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 6: 部署任意 GitHub 仓库
# ==============================================================================

deploy_custom_repo() {
  echo ""
  read -r -p "请输入仓库名 (如 vps-gdrive-backup 或 owner/repo，留空取消): " custom_r
  [ -z "$custom_r" ] && return
  read -r -p "是否为私有仓库？[y/N]: " is_priv
  if [[ "$is_priv" =~ ^[Yy]$ ]]; then
    deploy_project "$custom_r" "private" ""
  else
    deploy_project "$custom_r" "public" ""
  fi
}

# ==============================================================================
# 主菜单与 CLI 路由
# ==============================================================================

main_menu() {
  while true; do
    clear
    render_dashboard
    echo ""
    echo -e "  ${CYAN}1)${NC} ${BOLD}个人项目一键部署${NC}      ${DIM}(运维监控 / 节点面板 / AI网关 / 量化 — 共 22 项)${NC}"
    echo -e "  ${CYAN}2)${NC} ${BOLD}已安装项目 & 容器管理${NC}  ${DIM}(/opt 项目批量更新 / Docker 日志与重启 / 端口)${NC}"
    echo -e "  ${CYAN}3)${NC} ${BOLD}常用开源服务一键安装${NC}   ${DIM}(Docker / Nginx / Caddy / Node22 / Python / 1Panel)${NC}"
    echo -e "  ${CYAN}4)${NC} ${BOLD}系统调优与运维急救箱${NC}   ${DIM}(BBR / Swap / 深度清理 / 时区 / 进程 / 网络体检)${NC}"
    echo -e "  ${CYAN}5)${NC} ${BOLD}凭证、镜像源与自更新${NC}   ${DIM}(本机 Token 管理 / 加速切换 / 面板更新)${NC}"
    echo -e "  ${CYAN}6)${NC} ${BOLD}部署任意 GitHub 仓库${NC}   ${DIM}(输入仓库名自动克隆并嗅探部署脚本)${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}0) 退出控制面板        提示：随时输入 toolbox 可重新唤起本面板${NC}"
    echo ""
    read -r -p "请输入功能编号 [0-6]: " choice
    case "$choice" in
      1) menu_projects ;;
      2) menu_manage_installed ;;
      3) menu_services ;;
      4) menu_ops ;;
      5) menu_settings ;;
      6) deploy_custom_repo ;;
      0)
        echo -e "${GREEN}已退出 He's Linux Toolbox，再见！${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}输入有误，请输入 0-6 之间的数字！${NC}"
        sleep 1
        ;;
    esac
  done
}

case "${1:-}" in
  status)
    render_dashboard
    ;;
  deploy)
    shift
    if [ -z "${1:-}" ]; then
      echo "用法: toolbox deploy <repo-name> [public|private]"
      exit 1
    fi
    deploy_project "$1" "${2:-public}" ""
    ;;
  update)
    self_update
    ;;
  -h|--help|help)
    echo "He's Linux Toolbox v${HE_TOOLBOX_VERSION}"
    echo "用法:"
    echo "  toolbox                       打开交互式控制面板"
    echo "  toolbox status                输出当前服务器实时遥测看板"
    echo "  toolbox deploy <repo> [priv]  一键部署指定项目"
    echo "  toolbox update                自更新工具箱"
    ;;
  *)
    require_root || exit 1
    main_menu
    ;;
esac
