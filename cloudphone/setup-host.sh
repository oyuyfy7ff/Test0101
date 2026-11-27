#!/usr/bin/env bash
# เตรียมเครื่อง Ubuntu (22.04/24.04) ให้รันคลาวด์โฟนได้
# ใช้: sudo ./setup-host.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "กรุณารันด้วย sudo" >&2
  exit 1
fi

echo "==> ติดตั้ง Docker"
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl
  curl -fsSL https://get.docker.com | sh
fi

echo "==> ติดตั้งโมดูล kernel ของ Android (binder)"
apt-get install -y "linux-modules-extra-$(uname -r)" || \
  echo "!! ไม่พบ linux-modules-extra สำหรับ kernel นี้ (อาจมี binder ในตัวอยู่แล้ว)"

modprobe binder_linux devices="binder,hwbinder,vndbinder"

# โหลดโมดูลทุกครั้งที่บูตเครื่อง
echo 'binder_linux' > /etc/modules-load.d/cloudphone.conf
echo 'options binder_linux devices="binder,hwbinder,vndbinder"' > /etc/modprobe.d/cloudphone.conf

if grep -q binder /proc/filesystems || ls /dev/binder* >/dev/null 2>&1; then
  echo "==> พร้อมแล้ว: binder ใช้งานได้"
else
  echo "!! ยังไม่พบ binder: kernel นี้อาจไม่รองรับ ลองใช้ Ubuntu แบบ generic kernel" >&2
  exit 1
fi
