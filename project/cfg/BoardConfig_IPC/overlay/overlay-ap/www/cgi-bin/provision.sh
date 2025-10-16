#!/bin/sh
echo "Content-Type: text/html; charset=utf-8"
echo ""

# 读取 application/x-www-form-urlencoded
read POST_DATA
# 简单解析（只取 ssid/pass 两项）
SSID=$(printf '%s' "$POST_DATA" | sed -n 's/.*ssid=\([^&]*\).*/\1/p' | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf '%b')
PASS=$(printf '%s' "$POST_DATA" | sed -n 's/.*pass=\([^&]*\).*/\1/p' | sed 's/+/ /g;s/%/\\x/g' | xargs -0 printf '%b')

# 生成 wpa_supplicant.conf（使用 wpa_passphrase 确保转义安全）
CONF=/etc/wpa_supplicant.conf
TMP=/tmp/wc.$$
trap "rm -f $TMP" EXIT

if [ -z "$SSID" ]; then
  echo "<p>SSID 为空。</p>"; exit 0
fi

# 允许空密码用于开放热点，但主流 AP 为 WPA2/WPA3，这里按 WPA-PSK 处理
if [ -n "$PASS" ]; then
  wpa_passphrase "$SSID" "$PASS" > "$TMP"
else
  # 开放网络
  cat > "$TMP" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid="$SSID"
    key_mgmt=NONE
}
EOF
fi

mv "$TMP" "$CONF"
sync

# 重启 Wi-Fi 服务（S48wifi-provision：先 STA，失败回落 AP）
if /etc/init.d/S48wifi-provision restart >/dev/null 2>&1; then
  echo "<p>已提交，正在尝试连接 <b>$SSID</b> ……</p>"
  echo "<p>页面将自动跳转查看状态。</p>"
else
  echo "<p>提交完成，但重启 Wi-Fi 服务失败，请手动执行：<code>/etc/init.d/S48wifi-provision restart</code></p>"
fi
