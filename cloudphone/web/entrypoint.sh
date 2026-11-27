#!/bin/sh
# เชื่อม adb กับโทรศัพท์ทุกเครื่อง (cp-phone-1 ถึง cp-phone-$MAX_PHONES) ซ้ำทุก 15 วินาที
# เครื่องที่เพิ่ง เปิด/รีสตาร์ท จะขึ้นในหน้าเว็บเองโดยอัตโนมัติ
MAX_PHONES="${MAX_PHONES:-20}"

adb start-server

(
  while true; do
    i=1
    while [ "$i" -le "$MAX_PHONES" ]; do
      if getent hosts "cp-phone-$i" >/dev/null 2>&1; then
        adb connect "cp-phone-$i:5555" >/dev/null 2>&1
      fi
      i=$((i + 1))
    done
    sleep 15
  done
) &

exec node index.js
