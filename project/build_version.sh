#!/bin/sh
# /usr/local/sbin/update-buildinfo.sh
# 作用：增量更新 /etc/buildinfo 的版本（仅 patch 位）并写入当前构建时间
# 兼容 BusyBox / ash

set -eu

echo ${PWD}

BUILD_INFO_FILE=cfg/BoardConfig_IPC/overlay/overlay-ssh/etc/buildinfo

TMP="${BUILD_INFO_FILE}.tmp"
touch $TMP
# 1) 读当前版本（兼容两种格式）
cur_ver=""
if [ -f "$BUILD_INFO_FILE" ]; then
cur_ver=$(sed -n \
    -e 's/^VERSION=\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' \
    -e 's/^Version[[:space:]]*:[[:space:]]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)[[:space:]]*$/\1/p' \
    "$BUILD_INFO_FILE" | head -n1 || true)
fi

# 2) 解析与 +1（默认从 0.0.0 开始）
[ -n "${cur_ver}" ] || cur_ver="0.0.0"
OLD_IFS="$IFS"; IFS=.
set -- $cur_ver
IFS="$OLD_IFS"

MAJOR="${1:-0}"
MINOR="${2:-0}"
PATCH="${3:-0}"

# PATCH 可能有前导零或被空置；用 sed/expr 做十进制自增，避免八进制陷阱
# 仅保留数字
PATCH="$(printf '%s' "$PATCH" | sed 's/[^0-9].*$//')"
# 去前导零
PATCH="$(printf '%s' "$PATCH" | sed 's/^0\+//')"
[ -z "$PATCH" ] && PATCH=0
# 十进制 +1
PATCH="$(expr "$PATCH" + 1)"

new_ver="${MAJOR}.${MINOR}.${PATCH}"

BUILDTIME="$(TZ=UTC-8 date +%Y-%m-%dT%H:%M:%S)"

# 4) 原子写入
umask 022
{
    echo "VERSION=${new_ver}"
    echo "BUILDTIME=${BUILDTIME}"
    echo "BUILD_HOST=$(uname -n 2>/dev/null || echo buildhost)"
} > "$TMP"
mv -f "$TMP" "$BUILD_INFO_FILE"
echo "Updated /etc/buildinfo -> VERSION=${new_ver}, BUILDTIME=${BUILDTIME}"
