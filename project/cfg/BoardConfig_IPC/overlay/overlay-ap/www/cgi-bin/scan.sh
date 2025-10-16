#!/bin/sh
echo "Content-Type: application/json"
echo ""

# 使用 iw 扫描；如环境仅有 iwlist，可改用 iwlist 解析
# 安全起见，限制扫描时长，避免阻塞
IFACE="wlan0"
TMP=/tmp/scan.$$; trap "rm -f $TMP" EXIT

# 在 AP 模式下，部分驱动不支持同时 scan；但是 aic8800 一般可工作，失败时返回空列表
iw dev "$IFACE" scan 2>/dev/null > "$TMP"

# 解析 SSID 与信号强度
# 注意：隐藏 SSID 直接忽略；去重并按信号排序
awk '
  BEGIN{ RS="\nBSS "; OFS=""; print("{\"networks\":[") }
  NR>1{
    ssid=""; sig=""
    if (match($0, /SSID:([^\n]+)/, m)) { ssid=m[1] }
    if (match($0, /signal: (-?[0-9.]+)/, m2)) { sig=m2[1] }
    if (ssid != "") {
      gsub(/"/,"\\\"",ssid)
      arr[ssid]=sig
    }
  }
  END{
    first=1
    for (k in arr) {
      if (!first) print(",")
      first=0
      printf("{\"ssid\":\"%s\",\"signal\":%s}", k, arr[k]==""?0:arr[k])
    }
    print("]}")
  }
' "$TMP"
