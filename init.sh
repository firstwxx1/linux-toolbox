#!/usr/bin/env bash
# ==============================================================================
# He's Linux Toolbox — 一键引导与安装脚本
# 用法:
#   bash <(curl -fsSL https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main/init.sh)
# 安装后可直接运行:
#   toolbox          # 启动交互式运维与部署面板
#   toolbox status   # 快速查看服务器状态
#   toolbox deploy <repo>
#   toolbox update   # 更新工具箱至最新版本
# ==============================================================================

set -u

REPO_RAW_BASE="https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main"
URL_MAIN="${REPO_RAW_BASE}/tools.sh"
MIRRORS=(
  "https://ghfast.top/${URL_MAIN}"
  "https://gh-proxy.com/${URL_MAIN}"
  "https://mirror.ghproxy.com/${URL_MAIN}"
)

INSTALL_DIR="/usr/local/lib/he-toolbox"
SCRIPT_PATH="${INSTALL_DIR}/tools.sh"
BIN_TOOLBOX="/usr/local/bin/toolbox"
BIN_HE="/usr/local/bin/he"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 权限检查：非 root 时自动尝试 sudo
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO] 检测到非 root 用户，尝试通过 sudo 提权运行...${NC}"
    exec sudo -E bash "$0" "$@"
  else
    echo -e "${RED}[ERR] 请使用 root 权限运行本脚本 (sudo -i)${NC}"
    exit 1
  fi
fi

# 确保 curl 可用
if ! command -v curl >/dev/null 2>&1; then
  echo -e "${YELLOW}[INFO] 正在安装 curl...${NC}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 && apt-get install -y curl ca-certificates >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates >/dev/null 2>&1
  fi
fi

mkdir -p "$INSTALL_DIR"
TMP_FILE="$(mktemp)"

download_ok=0
echo -e "${CYAN}[INFO] 正在拉取最新版 He's Linux Toolbox...${NC}"

if curl -fsSL --connect-timeout 6 --max-time 25 "$URL_MAIN" -o "$TMP_FILE" 2>/dev/null && grep -q "HE_TOOLBOX_VERSION" "$TMP_FILE"; then
  download_ok=1
else
  echo -e "${YELLOW}[WARN] GitHub 直连受限，尝试国内镜像加速节点...${NC}"
  for m_url in "${MIRRORS[@]}"; do
    if curl -fsSL --connect-timeout 6 --max-time 25 "$m_url" -o "$TMP_FILE" 2>/dev/null && grep -q "HE_TOOLBOX_VERSION" "$TMP_FILE"; then
      download_ok=1
      echo -e "${GREEN}[OK] 已通过加速镜像拉取成功${NC}"
      break
    fi
  done
fi

if [ "$download_ok" -ne 1 ]; then
  rm -f "$TMP_FILE"
  echo -e "${RED}[ERR] 拉取 tools.sh 失败，请检查网络连接或稍后重试。${NC}"
  exit 1
fi

tr -d '\r' < "$TMP_FILE" > "$SCRIPT_PATH"
rm -f "$TMP_FILE"
chmod +x "$SCRIPT_PATH"

ln -sf "$SCRIPT_PATH" "$BIN_TOOLBOX"
if [ ! -e "$BIN_HE" ] || [ -L "$BIN_HE" ]; then
  ln -sf "$SCRIPT_PATH" "$BIN_HE"
fi

echo -e "${GREEN}[OK] 安装完成！以后任意目录输入 ${CYAN}toolbox${GREEN} 即可快速启动面板。${NC}"
exec bash "$SCRIPT_PATH" "$@"
