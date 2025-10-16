#!/bin/sh
echo "Content-Type: text/html; charset=utf-8"
echo ""

IP=$(ip -4 addr show dev wlan0 | awk '/inet /{print $2}' | cut -d/ -f1)
ROUTE=$(ip route show default 2>/dev/null | awk '/default/{print $3}')
SSID=$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '/^ssid=/{print $2}')
STATE=$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '/^wpa_state=/{print $2}')

echo "<h3>联网状态</h3>"
echo "<ul>"
echo "<li>State：${STATE:-N/A}</li>"
echo "<li>SSID：${SSID:-N/A}</li>"
echo "<li>IP：${IP:-未获取}</li>"
[ -n "$ROUTE" ] && echo "<li>Gateway：$ROUTE</li>"
echo "</ul>"

if [ -n "$IP" ]; then
  echo "<p>✅ 已连接到上游 Wi-Fi，可关闭本 AP。</p>"
else
  echo "<p>❌ 未连接上游 Wi-Fi，<a href='/'>返回重新配置</a> 或稍后刷新本页。</p>"
fi
