#!/usr/bin/env bash
# fix-perms-ext4.sh
# 作用：在已打包的 ext4 rootfs 镜像上修改文件/目录权限与属主
# 依赖：bash, mount, umount, losetup, partprobe/parted(可选), e2fsck
# 用法示例：
#   sudo ./fix-perms-ext4.sh output/image/rootfs.img
#
# 修改清单写法（下方 PERM_ENTRIES 数组）：
#   "<绝对路径>::<uid>:<gid>:<八进制权限>"
#   例如："/root/.ssh/authorized_keys::0:0:0600"

set -euo pipefail

# ========【1) 修改清单：把你的需求写到这里】========
# 说明：
# - 路径必须是镜像内部的绝对路径（以 / 开头）
# - uid/gid 必须是“数值”；mode 必须是“八进制”（如 0600/0755）
declare -a PERM_ENTRIES=(
  "/root/.ssh::0:0:0700"
  "/root::0:0:0700"
  "/root/.ssh/authorized_keys::0:0:0600"
  "/data/ssh::0:0:0700"
  "/etc/init.d/S20ssh-hostkeys::0:0:0755"
  # "/etc/ssh/ssh_host_ed25519_key::0:0:0600"
  # "/etc/ssh::0:0:0700"
  # "/etc/ssh/ssh_host_ed25519_key.pub::0:0:0644"
  # 如需更多，按行追加：
  # "/www/cgi-bin::0:0:0755"
  # "/www/cgi-bin/scan.sh::0:0:0755"
)

# ========【2) 通用函数】========
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() { [ "$EUID" -eq 0 ] || die "请用 sudo 运行"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

cleanup() {
  set +e
  if mountpoint -q "$MNT"; then umount "$MNT"; fi
  [ -n "${LOOPDEV:-}" ] && losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
  rmdir "$MNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ========【3) 参数与准备】========
need_root
IMG="${1:-}"
[ -n "$IMG" ] || die "用法：sudo $0 <rootfs.img>"

[ -f "$IMG" ] || die "镜像不存在：$IMG"

# 尝试识别类型
FILE_OUT=$(file -b "$IMG")
[[ "$FILE_OUT" =~ ext4 ]] || die "该脚本仅处理 ext2/3/4。检测到：$FILE_OUT"

MNT="$(mktemp -d /tmp/mnt-rootfs.XXXXXX)"
LOOPDEV=""

# ========【4) 计算挂载参数（是否带分区表）】========
# 尝试直接 loop 挂载；失败则尝试按分区偏移挂载
try_mount() {
  mount -o loop,ro "$IMG" "$MNT" 2>/dev/null
}

try_mount_with_offset() {
  # 使用 fdisk/parted 读取第一个 Linux 分区的起始字节偏移
  if have_cmd parted; then
    # 取第一个分区的 Start(字节) 与 Filesystem 类型包含 ext
    local startB
    startB=$(parted -s "$IMG" unit B print | awk '/^  [0-9]+/ {print $2; exit}' | tr -d B)
    [ -n "$startB" ] || return 1
    mount -o "loop,ro,offset=$startB" "$IMG" "$MNT"
    return $?
  fi

  if have_cmd fdisk; then
    # fdisk -l 输出扇区号，需乘以每扇区字节（一般 512）
    local sector_size startS
    sector_size=$(fdisk -l "$IMG" | awk '/Sector size/ {print $4; exit}')
    [ -z "$sector_size" ] && sector_size=512
    startS=$(fdisk -l "$IMG" | awk '/^Device .* Start/ {hdr=1; next} hdr && /^[^ ]/ {print $2; exit}')
    [ -n "$startS" ] || return 1
    local offset=$((startS * sector_size))
    mount -o "loop,ro,offset=$offset" "$IMG" "$MNT"
    return $?
  fi
  return 1
}

echo "[i] 尝试挂载镜像（只读探测）…"
if ! try_mount; then
  echo "[i] 直接挂载失败，尝试按分区偏移挂载…"
  try_mount_with_offset || die "无法挂载镜像。若为整盘镜像，请确保安装了 parted/fdisk。"
fi
umount "$MNT"

# ========【5) 以可写方式挂载并修改】========
# 为了稳妥，创建独立 loop 设备，便于回收
LOOPDEV=$(losetup --show -f "$IMG") || die "losetup 失败"
# 再次判断是否需要 offset：如果能直接 mount，就直接；否则按分区偏移
if mount -o rw "$LOOPDEV" "$MNT" 2>/dev/null; then
  :
else
  # 释放并重新创建带偏移的 loop
  losetup -d "$LOOPDEV"
  if have_cmd partx; then partx -u "$IMG" >/dev/null 2>&1 || true; fi
  # 计算偏移（同上）
  if have_cmd parted; then
    startB=$(parted -s "$IMG" unit B print | awk '/^  [0-9]+/ {print $2; exit}' | tr -d B)
    [ -n "$startB" ] || die "无法获取分区偏移"
    LOOPDEV=$(losetup --show -f -o "$startB" "$IMG") || die "losetup 带偏移失败"
    mount -o rw "$LOOPDEV" "$MNT" || die "挂载失败（带偏移）"
  else
    sector_size=$(fdisk -l "$IMG" | awk '/Sector size/ {print $4; exit}')
    [ -z "$sector_size" ] && sector_size=512
    startS=$(fdisk -l "$IMG" | awk '/^Device .* Start/ {hdr=1; next} hdr && /^[^ ]/ {print $2; exit}')
    [ -n "$startS" ] || die "无法获取分区起始扇区"
    offset=$((startS * sector_size))
    LOOPDEV=$(losetup --show -f -o "$offset" "$IMG") || die "losetup 带偏移失败"
    mount -o rw "$LOOPDEV" "$MNT" || die "挂载失败（带偏移）"
  fi
fi

echo "[i] 挂载点：$MNT"
echo "[i] 开始应用权限/属主变更…"

fail=0
for entry in "${PERM_ENTRIES[@]}"; do
  # 解析 <path>::<uid>:<gid>:<mode>
    path="${entry%%::*}"          # 取 '::' 左侧（path）
    rest="${entry#*::}"           # 取 '::' 右侧（uid:gid:mode）
    IFS=':' read -r uid gid mode <<<"$rest"

  [ -n "$path" ] || { echo "  [!] 空路径，跳过"; continue; }
  target="$MNT$path"
  if [ ! -e "$target" ]; then
    echo "  [!] 缺失：$path（镜像中不存在）"
    fail=1
    continue
  fi
  # 应用 chown / chmod
  chown "$uid:$gid" "$target" || { echo "  [x] chown 失败：$path"; fail=1; continue; }
  chmod "$mode"     "$target" || { echo "  [x] chmod 失败：$path"; fail=1; continue; }
  echo "  [+] OK  $path  →  uid:gid=$uid:$gid  mode=$mode"
done

echo "[i] 写回并卸载…"
sync
umount "$MNT"
losetup -d "$LOOPDEV"
rmdir "$MNT"

echo "[i] 运行 e2fsck 校验镜像…"
e2fsck -fy "$IMG" >/dev/null || true

if [ "$fail" -eq 0 ]; then
  echo "[✓] 全部修改完成。"
else
  echo "[!] 存在未生效的条目（见上方 [!] 或 [x]），请检查路径是否正确或先在镜像中创建该文件。"
fi
