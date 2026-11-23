#!/usr/bin/env bash
# ==============================================================================
# He's Linux Toolbox v3.0 — 全量 32 项目统一终端部署面板 & VPS 运维中枢
# Repository: https://github.com/firstwxx1/linux-toolbox
# ==============================================================================

HE_TOOLBOX_VERSION="3.0.0"
GITHUB_OWNER="firstwxx1"
REPO_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_OWNER}/linux-toolbox/main"
CONFIG_DIR="${HOME}/.config/he-toolbox"
TOKEN_FILE="${CONFIG_DIR}/github_token"
MIRROR_CONF="${CONFIG_DIR}/mirror_mode"
OPT_ROOT="/opt"

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

CACHED_PUBLIC_IP=""

# ==============================================================================
# 全量 33 项目统一注册表 (格式: "分类|仓库名|public/private|一句话简介")
# 所有仓库根目录均已接入标准化 panel.sh 协议 (status/install/start/update/logs)
# ==============================================================================

PROJECT_CATALOG=(
  "运维安全|vps-gdrive-backup|public|Google Drive 5TB 多节点备份与管理面板"
  "运维安全|vps-security-monitor|public|VPS 安全巡检与 Telegram 告警守卫"
  "运维安全|ct8-auto-renew|public|CT8 免费主机自动续期脚本"
  "运维安全|1Panel|public|1Panel 现代化开源 Linux 运维面板"

  "节点网络|nodehub|public|多 VPS / 多节点代理主控管理系统"
  "节点网络|node-deploy|public|VLESS-Reality + Hy2 + SOCKS5 一键部署"
  "节点网络|hysteria2-installer|public|Hysteria 2 生产级一键部署与管理"
  "节点网络|agent2api-egress|public|mihomo 逐账号订阅出口与看门狗"
  "节点网络|substore-platform|private|SubStore 订阅商城 (NestJS + Next.js)"
  "节点网络|airport-stack|private|Xboard + NodeHub 整合同步平台"
  "节点网络|nodejs-argo|public|NodeJS Argo 隧道多协议部署工具"

  "AI网关|WorkBuddy-Proxy|public|WorkBuddy 网关 + 管理面板整合版"
  "AI网关|WorkBuddy-Daily|private|WorkBuddy 成长中心全能自动签到"
  "AI网关|claude-telegram-bot|private|Claude Code CLI Telegram 桥接机器人"
  "AI网关|sub2api-armor-break|private|Sub2API Armor-Break 二开网关"
  "AI网关|muse-video-installer|public|Muse Video 工作台一键安装面板"
  "AI网关|chatgpt2api-dsh|public|ChatGPT2API DSH 本地号池插件"
  "AI网关|dsh-jailbreak-workflow|public|DSH Prompt 工作流与文档站"
  "AI网关|dsh-purge|public|DSH Purge 工具包"
  "AI网关|jailbreaks|public|Prompt 提示词参考合集"

  "量化风控|bybit-demo-auto-protection|public|Bybit V5 模拟盘自动风控与止盈止损"
  "量化风控|okx-demo-auto-protection|public|OKX 模拟盘 AI 自动止盈止损推送"
  "量化风控|binance-orderflow-bot|private|Binance USD-M 订单流模拟系统"
  "量化风控|crypto-bot-vps|private|Freqtrade 本地化 Flask 安全运维面板"
  "量化风控|usdt-scanner|private|EVM 多链地址工具"

  "业务应用|Alle-gmail|public|AI 智能邮件聚合客户端"
  "业务应用|domain-mail-hub|public|Cloudflare Workers 批量域名测试邮箱与收件箱面板"
  "业务应用|ecommerce-automation|private|多平台电商自动化与 RPA 工作流"
  "业务应用|globalcharge|private|GlobalCharge 数字商品商城 (Medusa v2)"
  "业务应用|lumen-workbench|private|FIRSTWXX DESK 个人运维中枢与 AI 额度遥测工作台"
  "业务应用|personal-blog|private|全栈 Next.js + Prisma 个人博客系统"
)

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
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v yum >/dev/null 2>&1; then echo "yum"
  elif command -v apk >/dev/null 2>&1; then echo "apk"
  else echo "unknown"
  fi
}

pkg_install() {
  local mgr
  mgr="$(detect_pkg_mgr)"
  case "$mgr" in
    apt) apt-get update -y && apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    apk) apk add --no-cache "$@" ;;
    *) echo -e "${RED}[ERR] 未识别包管理器，请手动安装: $*${NC}"; return 1 ;;
  esac
}

ensure_base_cmd() {
  local cmd="$1"
  local pkg="${2:-$1}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] 自动安装依赖 ${pkg}...${NC}"
    pkg_install "$pkg"
  fi
}

get_mirror_mode() {
  [ -f "$MIRROR_CONF" ] && cat "$MIRROR_CONF" || echo "auto"
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
  [ -n "$(get_github_token)" ]
}

lookup_repo_visibility() {
  local target="$1"
  local entry cat name vis desc
  for entry in "${PROJECT_CATALOG[@]}"; do
    IFS='|' read -r cat name vis desc <<< "$entry"
    if [ "$name" = "$target" ]; then
      echo "$vis"
      return
    fi
  done
  echo "public"
}

prompt_token_if_missing() {
  local repo_label="$1"
  if has_github_token; then
    return 0
  fi
  echo -e "${YELLOW}[AUTH] 「${repo_label}」是私有仓库，当前机器尚未配置 GitHub Token。${NC}"
  echo -e "${DIM}提示：Token 仅安全保存在本机 ${TOKEN_FILE} (chmod 600)，绝不写入代码库。${NC}"
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

  if [ "$is_private" = "private" ]; then
    echo "$base_url"
    return
  fi

  local mode
  mode="$(get_mirror_mode)"
  [ "$mode" = "direct" ] && { echo "$base_url"; return; }
  [ "$mode" = "mirror" ] && { echo "https://ghfast.top/${base_url}"; return; }

  if curl -fsI --connect-timeout 3 --max-time 5 "https://github.com" >/dev/null 2>&1; then
    echo "$base_url"
  else
    echo "https://ghfast.top/${base_url}"
  fi
}

# ==============================================================================
# 实时系统状态看板
# ==============================================================================

get_public_ip() {
  if [ -n "$CACHED_PUBLIC_IP" ]; then
    echo "$CACHED_PUBLIC_IP"
    return
  fi
  local ip
  ip="$(curl -4 -fsS --connect-timeout 2 --max-time 3 https://api.ipify.org 2>/dev/null || curl -4 -fsS --connect-timeout 2 --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  CACHED_PUBLIC_IP="${ip:-未知}"
  echo "$CACHED_PUBLIC_IP"
}

render_dashboard() {
  local host os kernel ip bbr cpu_cores load mem_info swap_info disk_info docker_stat opt_count tok_stat mirror_mode

  host="$(hostname 2>/dev/null || echo unknown)"
  os="$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' | cut -c1-32)"
  [ -z "$os" ] && os="$(uname -s)"
  kernel="$(uname -r | cut -c1-22)"
  ip="$(get_public_ip)"

  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi bbr; then
    bbr="${GREEN}BBR ON${NC}"
  else
    bbr="${YELLOW}BBR OFF${NC}"
  fi

  cpu_cores="$(nproc 2>/dev/null || echo '?')"
  load="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo 'N/A')"
  mem_info="$(free -h 2>/dev/null | awk 'NR==2{print $3"/"$2}')"
  swap_info="$(free -h 2>/dev/null | awk 'NR==3{print $3"/"$2}')"
  [ -z "$swap_info" ] && swap_info="未配置"
  disk_info="$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')"

  if command -v docker >/dev/null 2>&1; then
    local running total
    running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    total="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
    docker_stat="${GREEN}${running}/${total} 容器${NC}"
  else
    docker_stat="${DIM}未安装${NC}"
  fi

  opt_count="$(find "$OPT_ROOT" -maxdepth 2 -name "panel.sh" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if has_github_token; then tok_stat="${GREEN}已配置${NC}"; else tok_stat="${YELLOW}未配置${NC}"; fi
  mirror_mode="$(get_mirror_mode)"

  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}${WHITE}He's Linux Toolbox${NC} ${CYAN}v${HE_TOOLBOX_VERSION}${NC}   ${DIM}全量 32 项目统一部署 & VPS 运维中枢${NC}"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
  printf "  主机: ${WHITE}%-24s${NC}  公网IP: ${CYAN}%s${NC}\n" "${host:0:24}" "${ip}"
  printf "  系统: %-28s  内核: %s\n" "${os:0:28}" "${kernel}"
  echo -e "  负载: ${WHITE}${cpu_cores}C${NC} (${load})  网络: ${bbr}  镜像: ${CYAN}${mirror_mode}${NC}"
  echo -e "  内存: ${WHITE}${mem_info:-N/A}${NC}  Swap: ${swap_info}  磁盘: ${WHITE}${disk_info:-N/A}${NC}"
  echo -e "  Docker: ${docker_stat}  已装面板: ${CYAN}${opt_count}${NC}/${#PROJECT_CATALOG[@]}  私有Token: ${tok_stat}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
}

# ==============================================================================
# 统一项目部署 & panel.sh 接入引擎
# ==============================================================================

is_installed_badge() {
  if [ -d "${OPT_ROOT}/$1" ]; then
    echo -e "${GREEN}[已装]${NC}"
  else
    echo -e "${DIM}[未装]${NC}"
  fi
}

open_or_deploy_project() {
  local repo_spec="$1"
  local visibility="${2:-}"
  local action="${3:-}" # ""=interactive panel.sh, "install", "status", "update"
  local full_repo repo_name target_dir

  if [[ "$repo_spec" == */* ]]; then
    full_repo="$repo_spec"
    repo_name="${repo_spec##*/}"
  else
    full_repo="${GITHUB_OWNER}/${repo_spec}"
    repo_name="$repo_spec"
  fi

  [ -z "$visibility" ] && visibility="$(lookup_repo_visibility "$repo_name")"
  target_dir="${OPT_ROOT}/${repo_name}"

  ensure_base_cmd git git
  ensure_base_cmd curl curl

  if [ "$visibility" = "private" ]; then
    prompt_token_if_missing "$full_repo" || { pause; return 1; }
  fi

  if [ ! -d "$target_dir" ]; then
    local clone_url
    clone_url="$(resolve_github_clone_url "$full_repo" "$visibility")"
    echo -e "${CYAN}[CLONE] 首次拉取 ${full_repo} -> ${target_dir} ...${NC}"
    if ! git_with_auth "$visibility" clone --depth=1 "$clone_url" "$target_dir"; then
      echo -e "${RED}[ERR] 拉取失败，请检查网络或本机 GitHub Token 权限。${NC}"
      pause
      return 1
    fi
    echo -e "${GREEN}[OK] 仓库拉取完成！${NC}"
  elif [ "$action" = "update" ]; then
    echo -e "${YELLOW}[PULL] 正在更新 ${repo_name} ...${NC}"
    (cd "$target_dir" && git_with_auth "$visibility" pull --ff-only || git_with_auth "$visibility" pull)
  fi

  # 优先调用各项目统一的 panel.sh 控制面板
  if [ -f "${target_dir}/panel.sh" ]; then
    chmod +x "${target_dir}/panel.sh"
    if [ -n "$action" ]; then
      bash "${target_dir}/panel.sh" "$action"
    else
      bash "${target_dir}/panel.sh"
    fi
    return 0
  fi

  # 兼容非本账号的任意外部仓库嗅探
  echo -e "${YELLOW}[INFO] 该仓库未包含 panel.sh，尝试自动嗅探部署脚本...${NC}"
  cd "$target_dir" || return 1
  for s in install.sh deploy.sh start.sh setup.sh menu.sh; do
    if [ -f "$s" ]; then
      chmod +x "$s"
      bash "$s"
      pause
      return 0
    fi
  done
  if [ -f "docker-compose.yml" ]; then
    docker compose up -d && docker compose ps
  else
    ls -la
  fi
  pause
}

# ==============================================================================
# 模块 1: 全量 33 项目分类 & 搜索部署中心
# ==============================================================================

render_category_menu() {
  local target_cat="$1"
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  项目分类: ${target_cat}${NC}   ${DIM}(选择任意项目即可拉取并进入其专属 panel.sh 面板)${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"

    local items=()
    local idx=1
    local entry cat name vis desc lock
    for entry in "${PROJECT_CATALOG[@]}"; do
      IFS='|' read -r cat name vis desc <<< "$entry"
      if [ "$target_cat" = "ALL" ] || [ "$cat" = "$target_cat" ]; then
        items+=("${name}|${vis}")
        lock=""
        [ "$vis" = "private" ] && lock="🔒"
        printf "  ${CYAN}%2d)${NC} %-26s %s %-3s ${DIM}%s${NC}\n" "$idx" "$name" "$(is_installed_badge "$name")" "$lock" "$desc"
        idx=$((idx + 1))
      fi
    done

    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "   0) 返回上一级"
    echo ""
    read -r -p "输入编号进入该项目面板 [0-$((idx - 1))]: " pick
    [ "$pick" = "0" ] && return
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -lt "$idx" ]; then
      local chosen="${items[$((pick - 1))]}"
      local rname="${chosen%%|*}"
      local rvis="${chosen##*|}"
      open_or_deploy_project "$rname" "$rvis" ""
    else
      echo -e "${RED}无效编号${NC}"; sleep 1
    fi
  done
}

search_projects_menu() {
  local kw="${1:-}"
  if [ -z "$kw" ]; then
    echo ""
    read -r -p "请输入搜索关键词 (如 okx / backup / node / ai / sub): " kw
  fi
  [ -z "$kw" ] && return

  local matches=()
  local idx=1
  local entry cat name vis desc lock
  echo -e "\n${CYAN}=== 搜索「${kw}」匹配结果 ===${NC}"
  for entry in "${PROJECT_CATALOG[@]}"; do
    IFS='|' read -r cat name vis desc <<< "$entry"
    if echo "${cat} ${name} ${desc}" | grep -qi "$kw"; then
      matches+=("${name}|${vis}")
      lock=""
      [ "$vis" = "private" ] && lock="🔒"
      printf "  ${CYAN}%2d)${NC} [%-6s] %-26s %s %-2s ${DIM}%s${NC}\n" "$idx" "$cat" "$name" "$(is_installed_badge "$name")" "$lock" "$desc"
      idx=$((idx + 1))
    fi
  done

  if [ "${#matches[@]}" -eq 0 ]; then
    echo -e "  ${YELLOW}未找到匹配「${kw}」的项目。${NC}"
    pause
    return
  fi

  echo ""
  read -r -p "输入编号进入该项目面板 (0 返回): " pick
  if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -lt "$idx" ]; then
    local chosen="${matches[$((pick - 1))]}"
    open_or_deploy_project "${chosen%%|*}" "${chosen##*|}" ""
  fi
}

menu_projects_hub() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [1] 个人 32 个 GitHub 项目统一部署中心${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}1)${NC} 🛡️  运维与安全监控       ${DIM}(vps-gdrive-backup / vps-security-monitor / ct8 / 1Panel — 4项)${NC}"
    echo -e "  ${CYAN}2)${NC} 🌐 节点代理与订阅平台   ${DIM}(nodehub / node-deploy / hy2 / agent2api / substore 等 — 8项)${NC}"
    echo -e "  ${CYAN}3)${NC} 🤖 AI 网关与提示词工具  ${DIM}(WorkBuddy / claude-bot / sub2api / muse-video 等 — 10项)${NC}"
    echo -e "  ${CYAN}4)${NC} 📈 量化风控与策略面板   ${DIM}(bybit / okx / binance / crypto-bot-vps 等 — 7项)${NC}"
    echo -e "  ${CYAN}5)${NC} 💼 业务与效率应用       ${DIM}(Alle-gmail / ecommerce-automation / globalcharge — 3项)${NC}"
    echo -e "  ${CYAN}6)${NC} 📋 查看全部 32 个项目总表"
    echo -e "  ${CYAN}s)${NC} 🔍 关键词模糊搜索项目直达面板"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请选择 [0-6/s]: " c
    case "$c" in
      1) render_category_menu "运维安全" ;;
      2) render_category_menu "节点网络" ;;
      3) render_category_menu "AI网关" ;;
      4) render_category_menu "量化风控" ;;
      5) render_category_menu "业务应用" ;;
      6) render_category_menu "ALL" ;;
      s|S) search_projects_menu ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 2: 全局已安装项目健康巡检 & 容器管理
# ==============================================================================

inspect_all_installed() {
  echo -e "\n${CYAN}────────────────────────────────────────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}项目名称                     | 分类       | 运行状态                 | 版本/提交日期${NC}"
  echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────────${NC}"

  local found=0
  while IFS= read -r psh; do
    [ -n "$psh" ] || continue
    found=1
    chmod +x "$psh" 2>/dev/null || true
    printf "  %s\n" "$(bash "$psh" status 2>/dev/null || echo "$(basename "$(dirname "$psh")") | status-err")"
  done < <(find "$OPT_ROOT" -maxdepth 2 -name "panel.sh" -type f 2>/dev/null | sort)

  if [ "$found" -eq 0 ]; then
    echo -e "  ${DIM}(当前 /opt 下尚未部署带 panel.sh 的项目，可在主菜单 [1] 中一键安装)${NC}"
  fi
  echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────────${NC}"
}

menu_manage_installed() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [2] 已安装项目巡检 & 容器管理中心${NC}"
    inspect_all_installed

    echo ""
    echo -e "${YELLOW}▶ Docker 容器一览:${NC}"
    if command -v docker >/dev/null 2>&1; then
      docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -n 12 | sed 's/^/  /'
    else
      echo -e "  ${DIM}(Docker 未安装)${NC}"
    fi

    echo -e "\n${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 进入某个已安装项目的 panel.sh 面板"
    echo -e "  2) 一键批量 git pull 更新全部 /opt 项目（自动适配私有 Token）"
    echo -e "  3) 查看指定 Docker 容器日志 (最近 80 行)"
    echo -e "  4) 重启指定 Docker 容器"
    echo -e "  5) Systemd 后台服务快捷管理 (启停/重启/查日志)"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请选择 [0-5]: " m_opt
    case "$m_opt" in
      1)
        read -r -p "输入项目目录名 (如 nodehub): " pdir
        if [ -n "$pdir" ] && [ -d "${OPT_ROOT}/${pdir}" ]; then
          open_or_deploy_project "$pdir" "" ""
        else
          echo -e "${RED}未找到 ${OPT_ROOT}/${pdir}${NC}"; pause
        fi
        ;;
      2)
        while IFS= read -r gitdir; do
          local d rname rvis
          d="$(dirname "$gitdir")"
          rname="$(basename "$d")"
          rvis="$(lookup_repo_visibility "$rname")"
          echo -e "${CYAN}>>> 更新 ${rname} (${rvis}) ...${NC}"
          if [ "$rvis" = "private" ] && ! has_github_token; then
            echo -e "${YELLOW}  [SKIP] 未配置本机 Token，跳过私有库 ${rname}${NC}"
          else
            (cd "$d" && git_with_auth "$rvis" pull --ff-only 2>/dev/null || echo -e "${YELLOW}  [WARN] ${rname} 存在本地改动或网络超时${NC}")
          fi
        done < <(find "$OPT_ROOT" -maxdepth 2 -name ".git" -type d 2>/dev/null | sort)
        pause
        ;;
      3)
        read -r -p "输入容器名: " cname
        [ -n "$cname" ] && docker logs --tail 80 "$cname"
        pause
        ;;
      4)
        read -r -p "输入要重启的容器名: " cname
        [ -n "$cname" ] && docker restart "$cname" && echo -e "${GREEN}[OK] 已重启 ${cname}${NC}"
        pause
        ;;
      5) menu_systemd_manager ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

menu_systemd_manager() {
  echo -e "\n${CYAN}=== 活跃 / 异常 Systemd 服务 ===${NC}"
  systemctl list-units --type=service --state=running,failed --no-pager | head -n 30
  echo ""
  read -r -p "输入服务名 (如 nginx / docker / mihomo / claude-telegram，回车返回): " svc
  [ -z "$svc" ] && return
  echo -e "  1) status   2) restart   3) stop   4) start   5) journalctl -n 60"
  read -r -p "操作 [1-5]: " act
  case "$act" in
    1) systemctl status "$svc" --no-pager | head -n 25 ;;
    2) systemctl restart "$svc" && echo -e "${GREEN}[OK] 已重启 ${svc}${NC}" ;;
    3) systemctl stop "$svc" && echo -e "${YELLOW}[OK] 已停止 ${svc}${NC}" ;;
    4) systemctl start "$svc" && echo -e "${GREEN}[OK] 已启动 ${svc}${NC}" ;;
    5) journalctl -u "$svc" -n 60 --no-pager ;;
  esac
  pause
}

# ==============================================================================
# 模块 3: 常用开源服务 + 一键 HTTPS 反代生成器
# ==============================================================================

svc_install_docker() {
  local mode="${1:-pause}"
  echo -e "${YELLOW}[INFO] 正在安装 Docker & Docker Compose...${NC}"
  if curl -fsI --connect-timeout 3 https://get.docker.com >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | bash
  else
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
  fi
  systemctl enable --now docker 2>/dev/null || true
  docker --version && docker compose version
  [ "$mode" = "pause" ] && pause
}

svc_install_caddy() {
  echo -e "${YELLOW}[INFO] 正在安装 Caddy (自动 HTTPS)...${NC}"
  local mgr
  mgr="$(detect_pkg_mgr)"
  if [ "$mgr" = "apt" ]; then
    apt-get update -y
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -y && apt-get install -y caddy
  else
    pkg_install caddy || true
  fi
  systemctl enable --now caddy 2>/dev/null || true
  echo -e "${GREEN}[OK] Caddy 已就绪！${NC}"
}

wizard_reverse_proxy() {
  echo -e "\n${CYAN}=== 一键 HTTPS 反向代理生成器 (Caddy 自动证书 / Nginx) ===${NC}"
  read -r -p "请输入已解析到本机的域名 (例如 panel.example.com): " domain
  [ -z "$domain" ] && return
  read -r -p "请输入本机上游服务端口 (例如 8999 或 3000): " port
  [ -z "$port" ] && return

  if command -v caddy >/dev/null 2>&1; then
    mkdir -p /etc/caddy/conf.d
    grep -q 'import /etc/caddy/conf.d/\*.caddy' /etc/caddy/Caddyfile 2>/dev/null || echo 'import /etc/caddy/conf.d/*.caddy' >> /etc/caddy/Caddyfile
    cat > "/etc/caddy/conf.d/${domain}.caddy" <<EOF
${domain} {
    encode gzip zstd
    reverse_proxy 127.0.0.1:${port}
}
EOF
    caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
    echo -e "${GREEN}[OK] Caddy 反代已生效！访问: https://${domain} -> 127.0.0.1:${port}${NC}"
  elif command -v nginx >/dev/null 2>&1; then
    local conf_file="/etc/nginx/conf.d/${domain}.conf"
    cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    nginx -t && systemctl reload nginx
    echo -e "${GREEN}[OK] Nginx 反代已生成 (${conf_file}) 并重载！如需 HTTPS 可配合 certbot --nginx。${NC}"
  else
    echo -e "${YELLOW}[INFO] 尚未安装 Caddy 或 Nginx，推荐先安装 Caddy (自动签发 HTTPS)。${NC}"
    read -r -p "是否立即安装 Caddy 并配置该反代？[y/N]: " ic
    if [[ "$ic" =~ ^[Yy]$ ]]; then
      svc_install_caddy
      wizard_reverse_proxy
      return
    fi
  fi
  pause
}

menu_services() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [3] 常用开源服务 & 一键 HTTPS 反代${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 安装 Docker + Docker Compose v2"
    echo -e "  2) 安装 Nginx Web 服务器"
    echo -e "  3) 安装 Caddy（自动签发 HTTPS 证书反代神器）"
    echo -e "  4) ${GREEN}一键配置域名 HTTPS 反向代理向导 (域名 -> 本机端口)${NC}"
    echo -e "  5) 安装 Node.js 22 LTS + pnpm + PM2"
    echo -e "  6) 安装 Python 3 + pip + venv + uv"
    echo -e "  7) 安装 1Panel v2 开源运维面板"
    echo -e "  8) 安装 Fail2ban + UFW 基础安全加固"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-8]: " s_opt
    case "$s_opt" in
      1) svc_install_docker ;;
      2) pkg_install nginx && systemctl enable --now nginx; pause ;;
      3) svc_install_caddy; pause ;;
      4) wizard_reverse_proxy ;;
      5)
        local mgr; mgr="$(detect_pkg_mgr)"
        if [ "$mgr" = "apt" ]; then curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt-get install -y nodejs
        else curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && "$mgr" install -y nodejs; fi
        npm install -g pnpm pm2
        echo -e "${GREEN}[OK] Node $(node -v) / pnpm / pm2 已安装${NC}"; pause
        ;;
      6)
        pkg_install python3 python3-pip python3-venv 2>/dev/null || pkg_install python3 python3-pip
        curl -LsSf https://astral.sh/uv/install.sh | sh || true
        pause
        ;;
      7) bash -c "$(curl -sSL https://resource.1panel.pro/v2/quick_start.sh)"; pause ;;
      8)
        pkg_install ufw fail2ban
        ufw allow 22/tcp >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        systemctl enable --now fail2ban 2>/dev/null || true
        echo -e "${GREEN}[OK] Fail2ban 已启用；UFW 已放行 22/80/443（如需开启请运行 ufw enable）${NC}"; pause
        ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 4: 系统调优、Crontab、SSH 加固与运维急救箱
# ==============================================================================

ops_enable_bbr() {
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi bbr; then
    echo -e "${GREEN}[OK] BBR 已开启！${NC}"
  else
    grep -q '^net.core.default_qdisc=fq' /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q '^net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${GREEN}[OK] BBR 已生效！${NC}"
  fi
  pause
}

ops_manage_swap() {
  free -h
  echo -e "\n  1) 1G Swap   2) 2G Swap   3) 4G Swap   4) 移除 Swap   0) 返回"
  read -r -p "选择 [0-4]: " sw
  local size_mb=0
  case "$sw" in
    1) size_mb=1024 ;;
    2) size_mb=2048 ;;
    3) size_mb=4096 ;;
    4)
      swapoff /swapfile 2>/dev/null || true; rm -f /swapfile; sed -i '\|/swapfile|d' /etc/fstab
      echo -e "${GREEN}[OK] 已移除 /swapfile${NC}"; pause; return ;;
    *) return ;;
  esac
  swapoff /swapfile 2>/dev/null || true; rm -f /swapfile
  fallocate -l "${size_mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$size_mb" status=progress
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  free -h
  pause
}

ops_manage_cron() {
  echo -e "\n${CYAN}=== 当前 Crontab 定时任务 ===${NC}"
  crontab -l 2>/dev/null | nl -ba || echo "(当前无定时任务)"
  echo ""
  echo -e "  1) 新增一条定时任务"
  echo -e "  2) 按关键词删除定时任务"
  echo -e "  3) 打开 crontab -e 编辑"
  echo -e "  0) 返回"
  read -r -p "选择 [0-3]: " cr
  case "$cr" in
    1)
      read -r -p "输入完整 cron 行 (如 0 4 * * * /opt/ct8-auto-renew/panel.sh start): " line
      if [ -n "$line" ]; then
        (crontab -l 2>/dev/null; echo "$line") | crontab -
        echo -e "${GREEN}[OK] 已添加定时任务${NC}"
      fi
      ;;
    2)
      read -r -p "输入要删除任务包含的关键词: " kw
      if [ -n "$kw" ]; then
        crontab -l 2>/dev/null | grep -v "$kw" | crontab -
        echo -e "${GREEN}[OK] 已移除匹配「${kw}」的任务${NC}"
      fi
      ;;
    3) crontab -e ;;
  esac
  pause
}

ops_ssh_hardening() {
  echo -e "\n${CYAN}=== SSH 安全状态与公钥助手 ===${NC}"
  echo -e "当前 SSH 端口: $(grep -E '^[[:space:]]*Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo '22 (默认)')"
  echo -e "已授权公钥数:  $(wc -l < "${HOME}/.ssh/authorized_keys" 2>/dev/null || echo 0)"
  echo ""
  echo -e "  1) 添加一条 SSH 公钥到 ${HOME}/.ssh/authorized_keys"
  echo -e "  2) 查看近期 SSH 爆破失败 IP Top 10"
  echo -e "  3) 备份当前 /etc/ssh/sshd_config"
  echo -e "  0) 返回"
  read -r -p "选择 [0-3]: " sh_opt
  case "$sh_opt" in
    1)
      read -r -p "粘贴 ssh-ed25519 / ssh-rsa 公钥内容: " pubk
      if [ -n "$pubk" ]; then
        mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
        echo "$pubk" >> "${HOME}/.ssh/authorized_keys"
        chmod 600 "${HOME}/.ssh/authorized_keys"
        echo -e "${GREEN}[OK] 公钥已导入！${NC}"
      fi
      ;;
    2)
      journalctl -u ssh -u sshd -n 2000 --no-pager 2>/dev/null | grep -iE 'Failed password|Invalid user' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | head -n 10 || echo "暂无日志"
      ;;
    3)
      cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
      echo -e "${GREEN}[OK] 已备份 /etc/ssh/sshd_config${NC}"
      ;;
  esac
  pause
}

menu_ops() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [4] 系统调优、定时任务、SSH 加固与急救箱${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 开启 TCP BBR + FQ 网络加速（幂等防重复）"
    echo -e "  2) 智能管理 Swap 虚拟内存（1G / 2G / 4G / 移除）"
    echo -e "  3) 清理系统缓存、3天前日志与 Docker 悬空镜像"
    echo -e "  4) 新机初始化（上海时区 + curl/git/vim/htop/jq/lsof）"
    echo -e "  5) 进程高负载 Top10 与监听端口速查"
    echo -e "  6) 网络出口归属地与 GitHub/DNS 延迟体检"
    echo -e "  7) Crontab 定时任务可视化管理"
    echo -e "  8) SSH 公钥导入与爆破 IP 排查助手"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-8]: " o_opt
    case "$o_opt" in
      1) ops_enable_bbr ;;
      2) ops_manage_swap ;;
      3)
        local mgr; mgr="$(detect_pkg_mgr)"
        case "$mgr" in
          apt) apt-get autoremove -y && apt-get clean ;;
          dnf) dnf autoremove -y && dnf clean all ;;
          yum) yum clean all ;;
        esac
        command -v journalctl >/dev/null 2>&1 && journalctl --vacuum-time=3d
        if command -v docker >/dev/null 2>&1; then
          read -r -p "同时清理 Docker 悬空镜像与缓存？[y/N]: " pd
          [[ "$pd" =~ ^[Yy]$ ]] && docker system prune -f
        fi
        df -h /; pause
        ;;
      4)
        timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        pkg_install curl wget git vim htop jq unzip tar ca-certificates lsof
        echo -e "${GREEN}[OK] 当前时间: $(date)${NC}"; pause
        ;;
      5)
        echo -e "${CYAN}=== Top 10 内存进程 ===${NC}"
        ps aux --sort=-%mem | head -n 11
        echo -e "\n${CYAN}=== 监听端口 ===${NC}"
        ss -tulpn 2>/dev/null | head -n 25 || netstat -tulpn 2>/dev/null | head -n 25
        pause
        ;;
      6)
        echo -e "IPv4: $(curl -4 -fsS --max-time 4 https://ipinfo.io/json 2>/dev/null | tr '\n' ' ' | cut -c1-120 || get_public_ip)"
        for target in "github.com" "api.github.com" "1.1.1.1" "223.5.5.5"; do
          local ms; ms="$(ping -c 2 -W 2 "$target" 2>/dev/null | awk -F'/' 'END{if($5) print $5" ms"; else print "超时"}')"
          printf "  %-16s -> %s\n" "$target" "$ms"
        done
        pause
        ;;
      7) ops_manage_cron ;;
      8) ops_ssh_hardening ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 模块 5: 凭证、镜像源与自更新
# ==============================================================================

self_update() {
  echo -e "${YELLOW}[INFO] 正在更新 He's Linux Toolbox...${NC}"
  bash <(curl -fsSL "${REPO_RAW_BASE}/init.sh" || curl -fsSL "https://ghfast.top/${REPO_RAW_BASE}/init.sh") status
  echo -e "${GREEN}[OK] 工具箱已更新至最新版！${NC}"
}

menu_settings() {
  while true; do
    clear
    render_dashboard
    echo -e "\n${BOLD}${CYAN}  [5] 安全凭证、镜像源与工具箱自身管理${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  1) 配置 / 更新本机 GitHub Token (chmod 600，绝不写进仓库)"
    echo -e "  2) 校验当前 GitHub Token 连通性"
    echo -e "  3) 清除本机保存的 GitHub Token"
    echo -e "  4) 切换 GitHub 访问模式 (当前: ${CYAN}$(get_mirror_mode)${NC})"
    echo -e "  5) 自更新 toolbox 到最新版"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  0) 返回主菜单"
    echo ""
    read -r -p "请输入选项 [0-5]: " c_opt
    case "$c_opt" in
      1)
        read -r -s -p "请输入新的 GitHub PAT: " new_tok; echo ""
        if [ -n "$new_tok" ]; then
          init_config_dir; printf '%s' "$new_tok" > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"
          echo -e "${GREEN}[OK] Token 已保存。${NC}"
        fi
        pause
        ;;
      2)
        local tok; tok="$(get_github_token)"
        if [ -z "$tok" ]; then echo -e "${YELLOW}未配置 Token${NC}"
        else
          local login; login="$(curl -fsS -H "Authorization: Bearer ${tok}" https://api.github.com/user 2>/dev/null | grep -m1 '"login"' | cut -d'"' -f4)"
          [ -n "$login" ] && echo -e "${GREEN}[OK] Token 有效！认证用户: ${login}${NC}" || echo -e "${RED}[FAIL] Token 无效或网络超时${NC}"
        fi
        pause
        ;;
      3) rm -f "$TOKEN_FILE"; echo -e "${GREEN}[OK] 已清除本机 Token${NC}"; pause ;;
      4)
        init_config_dir
        echo -e "  1) auto (自动测速)   2) direct (直连)   3) mirror (加速镜像)"
        read -r -p "选择 [1-3]: " mm
        case "$mm" in 1) echo "auto" > "$MIRROR_CONF" ;; 2) echo "direct" > "$MIRROR_CONF" ;; 3) echo "mirror" > "$MIRROR_CONF" ;; esac
        echo -e "${GREEN}[OK] 当前模式: $(get_mirror_mode)${NC}"; pause
        ;;
      5) self_update; pause ;;
      0) return ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

# ==============================================================================
# 主菜单与 CLI 参数路由
# ==============================================================================

main_menu() {
  while true; do
    clear
    render_dashboard
    echo ""
    echo -e "  ${CYAN}1)${NC} ${BOLD}个人 32 项目一键部署${NC}   ${DIM}(已全部接入专属 panel.sh 统一部署面板)${NC}"
    echo -e "  ${CYAN}2)${NC} ${BOLD}已安装项目巡检 & 容器${NC}  ${DIM}(全局 panel.sh 健康状态表 / 批量更新 / Systemd)${NC}"
    echo -e "  ${CYAN}3)${NC} ${BOLD}开源服务 & 一键反代${NC}    ${DIM}(Docker / Caddy / Nginx / HTTPS 反代向导 / Node / 1Panel)${NC}"
    echo -e "  ${CYAN}4)${NC} ${BOLD}系统调优与安全急救箱${NC}   ${DIM}(BBR / Swap / 清理 / Crontab / SSH公钥 / 端口与延迟)${NC}"
    echo -e "  ${CYAN}5)${NC} ${BOLD}凭证、镜像源与自更新${NC}   ${DIM}(本机 Token 管理 / 加速模式 / toolbox update)${NC}"
    echo -e "  ${CYAN}s)${NC} ${BOLD}关键词秒搜项目直达${NC}     ${DIM}(输入关键词快速定位项目并打开其 panel.sh)${NC}"
    echo -e "  ${CYAN}d)${NC} ${BOLD}部署任意外部 GitHub 仓${NC} ${DIM}(输入 owner/repo 自动克隆并嗅探部署)${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}0) 退出面板     快捷CLI: toolbox [status|inspect|search|deploy|update]${NC}"
    echo ""
    read -r -p "请输入选项 [0-5/s/d]: " choice
    case "$choice" in
      1) menu_projects_hub ;;
      2) menu_manage_installed ;;
      3) menu_services ;;
      4) menu_ops ;;
      5) menu_settings ;;
      s|S) search_projects_menu ;;
      d|D)
        read -r -p "输入仓库 (如 repo 或 owner/repo): " cr
        if [ -n "$cr" ]; then
          read -r -p "是否私有仓库？[y/N]: " cp
          [[ "$cp" =~ ^[Yy]$ ]] && open_or_deploy_project "$cr" "private" "" || open_or_deploy_project "$cr" "public" ""
        fi
        ;;
      0) echo -e "${GREEN}已退出 He's Linux Toolbox，再见！${NC}"; exit 0 ;;
      *) echo -e "${RED}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  status)  render_dashboard ;;
  inspect) render_dashboard; inspect_all_installed ;;
  search)  shift; search_projects_menu "${1:-}" ;;
  deploy|panel)
    shift
    [ -z "${1:-}" ] && { echo "用法: toolbox deploy <repo-name> [public|private] [install|status|update]"; exit 1; }
    open_or_deploy_project "$1" "${2:-}" "${3:-}"
    ;;
  update)
    self_update
    exit 0
    ;;
  -h|--help|help)
    echo "He's Linux Toolbox v${HE_TOOLBOX_VERSION}"
    echo "用法:"
    echo "  toolbox                         打开交互式运维与部署控制面板"
    echo "  toolbox status                  查看当前服务器实时遥测看板"
    echo "  toolbox inspect                 全局巡检 /opt 下全部已装项目 panel.sh 状态"
    echo "  toolbox search <关键词>         关键词检索 32 个项目并进入对应面板"
    echo "  toolbox deploy <repo> [vis]     拉取并打开指定项目的 panel.sh 面板"
    echo "  toolbox update                  自更新工具箱至最新版"
    ;;
  *)
    require_root || exit 1
    main_menu
    ;;
esac
