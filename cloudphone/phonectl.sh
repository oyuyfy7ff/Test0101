#!/usr/bin/env bash
# จัดการคลาวด์โฟน: สร้าง / ปิด / เปิด / รีสตาร์ท / ลบ / ติดตั้งแอป
set -euo pipefail
cd "$(dirname "$0")"

NET=cloudphone
WEB=cp-web
IMAGE="${REDROID_IMAGE:-redroid/redroid:12.0.0_64only-latest}"
WIDTH="${PHONE_WIDTH:-720}"
HEIGHT="${PHONE_HEIGHT:-1280}"
DPI="${PHONE_DPI:-320}"
MEMORY="${PHONE_MEMORY:-3g}"
WEB_BIND="${WEB_BIND:-127.0.0.1}"   # ตั้ง WEB_BIND=0.0.0.0 เพื่อเปิดให้เข้าจากภายนอก (ไม่มีรหัสผ่าน!)
WEB_PORT="${WEB_PORT:-8000}"

phone() { echo "cp-phone-$1"; }

need_num() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "ต้องระบุหมายเลขเครื่อง เช่น: $0 $CMD 1" >&2; exit 1; }
}

ensure_net() {
  docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
}

next_free() {
  local i=1
  while docker container inspect "$(phone "$i")" >/dev/null 2>&1; do i=$((i + 1)); done
  echo "$i"
}

adb_web() { docker exec "$WEB" adb "$@"; }

CMD="${1:-help}"; shift || true

case "$CMD" in
  web)
    ensure_net
    docker build -t cloudphone-web ./web
    docker rm -f "$WEB" >/dev/null 2>&1 || true
    docker run -d --name "$WEB" --network "$NET" --restart unless-stopped \
      -p "$WEB_BIND:$WEB_PORT:8000" cloudphone-web >/dev/null
    echo "เปิดหน้าเว็บแล้ว: http://$WEB_BIND:$WEB_PORT"
    ;;

  add)
    ensure_net
    count="${1:-1}"
    for _ in $(seq "$count"); do
      n=$(next_free)
      docker run -d --name "$(phone "$n")" --network "$NET" --privileged \
        --restart unless-stopped --memory "$MEMORY" \
        -v "cp-data-$n:/data" \
        "$IMAGE" \
        androidboot.redroid_width="$WIDTH" \
        androidboot.redroid_height="$HEIGHT" \
        androidboot.redroid_dpi="$DPI" \
        androidboot.redroid_gpu_mode=guest >/dev/null
      echo "สร้างเครื่อง #$n แล้ว (ใช้เวลาบูตประมาณ 30-60 วินาที)"
    done
    ;;

  list)
    docker ps -a --filter "name=cp-phone-" \
      --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}'
    ;;

  stop|start|restart)
    need_num "${1:-}"
    docker "$CMD" "$(phone "$1")" >/dev/null
    echo "$CMD เครื่อง #$1 แล้ว"
    ;;

  remove)
    need_num "${1:-}"
    docker rm -f "$(phone "$1")" >/dev/null
    if [ "${2:-}" = "--wipe" ]; then
      docker volume rm "cp-data-$1" >/dev/null
      echo "ลบเครื่อง #$1 และข้อมูลทั้งหมดแล้ว"
    else
      echo "ลบเครื่อง #$1 แล้ว (ข้อมูลยังเก็บไว้ ใช้ --wipe เพื่อลบข้อมูลด้วย)"
    fi
    ;;

  install)
    need_num "${1:-}"
    apk="${2:-}"
    [ -f "$apk" ] || { echo "ไม่พบไฟล์ APK: $apk" >&2; exit 1; }
    docker cp "$apk" "$WEB:/tmp/app.apk"
    adb_web connect "$(phone "$1"):5555" >/dev/null
    adb_web -s "$(phone "$1"):5555" install -r /tmp/app.apk
    ;;

  shell)
    need_num "${1:-}"
    adb_web connect "$(phone "$1"):5555" >/dev/null
    docker exec -it "$WEB" adb -s "$(phone "$1"):5555" shell
    ;;

  *)
    cat <<EOF
ใช้งาน: $0 <คำสั่ง>

  web                     สร้างและเปิดหน้าเว็บควบคุม (ทำครั้งแรกครั้งเดียว)
  add [จำนวน]             สร้างโทรศัพท์ใหม่ (ค่าเริ่มต้น 1 เครื่อง)
  list                    ดูรายการโทรศัพท์ทั้งหมด
  stop|start|restart N    ปิด / เปิด / รีสตาร์ทเครื่องหมายเลข N
  remove N [--wipe]       ลบเครื่อง N (--wipe = ลบข้อมูลในเครื่องด้วย)
  install N ไฟล์.apk      ติดตั้งแอปลงเครื่อง N
  shell N                 เข้า shell ของเครื่อง N
EOF
    ;;
esac
