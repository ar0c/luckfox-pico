#!/bin/sh
# 动态 MOTD：构建信息 + 设备实时状态
[ -f /etc/buildinfo ] && cat /etc/buildinfo
echo "Uptime  : $(cut -d. -f1 /proc/uptime)s"
echo "LoadAvg : $(cut -d' ' -f1-3 /proc/loadavg)"
IP4=$(ip -4 -o addr show dev wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$IP4" ] && echo "wlan0   : $IP4"
IP4e=$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$IP4e" ] && echo "eth0    : $IP4e"
IP4u=$(ip -4 -o addr show dev usb0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
[ -n "$IP4u" ] && echo "usb0    : $IP4u"
echo
