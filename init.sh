#!/bin/bash
# 用法: bash <(curl -sL https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main/init.sh)

URL_MAIN="https://raw.githubusercontent.com/firstwxx1/linux-toolbox/main/tools.sh"
URL_MIRROR="https://ghproxy.com/$URL_MAIN"
SCRIPT_PATH="/root/he_tools.sh"

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

if ! command -v curl &> /dev/null; then
    apt-get update -y && apt-get install curl -y || yum install curl -y || dnf install curl -y
fi

HTTP_CODE=$(curl -I -m 3 -s -w "%{http_code}\n" -o /dev/null "$URL_MAIN")

if [ "$HTTP_CODE" -eq 200 ]; then
    DOWNLOAD_URL="$URL_MAIN"
else
    DOWNLOAD_URL="$URL_MIRROR"
fi

curl -sS -o "$SCRIPT_PATH" "$DOWNLOAD_URL"
if [ -f "$SCRIPT_PATH" ]; then
    chmod +x "$SCRIPT_PATH"
    bash "$SCRIPT_PATH" "$@"
else
    echo -e "${RED}拉取失败！${NC}"
    exit 1
fi
