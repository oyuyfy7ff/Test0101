# Skyfront

เกมวางแผนสงคราม 2D แนว grand strategy สร้างด้วย **Godot 4.3+** (renderer `gl_compatibility` รันบน Android ได้)
โครงสร้างโค้ดใช้แนวคิดจากพิมพ์เขียว (data-driven, ทุกการกระทำเป็นคำสั่ง, แผนที่เป็นเลเยอร์, AI เป็นผู้เล่นคนหนึ่ง)
แต่ชื่อเกม ชื่อประเทศ ภาพ และโค้ดทั้งหมดเขียนขึ้นใหม่ ไม่มีทรัพยากรจากเกมอื่น

## วิธีรัน

1. ติดตั้ง Godot 4.3 ขึ้นไป (เวอร์ชันมาตรฐาน ไม่ต้องใช้ .NET)
2. เปิด Godot แล้วกด **Import** เลือกไฟล์ `project.godot`
3. กด **F5** เพื่อเล่น

ถ้าจะ export ไป Android/PC ให้เพิ่ม `content/*` ใน *Export → Resources → Filters to export non-resource files* เพื่อให้ไฟล์ JSON ติดไปด้วย

## วิธีเล่น

| การกระทำ | ปุ่ม |
|---|---|
| เลื่อนแผนที่ | WASD / ลูกศร / ลากด้วยปุ่มกลางเมาส์ |
| ซูม | ล้อเมาส์ / pinch บน trackpad |
| เลือกทหาร | คลิกซ้าย หรือลากกรอบ (Shift = เพิ่ม) |
| สั่งเดิน/บุก | คลิกขวา |
| ยกเลิกโหมด/ยกเลิกการเลือก | Esc หรือคลิกขวา |
| หยุด / ความเร็ว | Space, 1, 2, 3 |
| เซฟ / โหลด | F5 / F9 |

- แท็บ **Build**: สร้างอาคารในดินแดนตัวเอง (บางอย่างต้องอยู่บนภูมิประเทศที่กำหนด เช่นเหมืองต้องอยู่บนเนินเขา/ภูเขา)
- แท็บ **Army**: เกณฑ์ทหาร (ทหารราบต้องมีค่ายทหาร, รถถัง/ปืนใหญ่ต้องมีโรงงานอาวุธ)
- แท็บ **Strike**: ยิงโดรน/ขีปนาวุธใส่ประเทศที่ทำสงครามด้วย ต้องมีฐานยิงในระยะ ฝ่ายตรงข้ามยิงสกัดได้ด้วย Air Defense
- แท็บ **Diplomacy**: ประกาศสงคราม ขอสันติภาพ ขอเป็นพันธมิตร ตอบรับข้อเสนอ
- แท็บ **Market**: ซื้อ/ขายทรัพยากร ราคาขยับตามการซื้อขาย
- ยึดเมืองหลวง (จุดสีเหลือง) ของประเทศใด ประเทศนั้นแพ้ทันที ชนะเมื่อเหลือแต่เราและพันธมิตร

## โครงสร้างโปรเจกต์

```
project.godot            ตั้งค่า Godot (autoload ContentDB)
main.tscn                ฉากเริ่มต้น → game/main/main.gd
content/                 ข้อมูลเกมทั้งหมดเป็น JSON (แก้ได้โดยไม่ต้องแตะโค้ด)
  resources/ buildings/ units/ strikes/
  overrides/overrides.json   แก้ค่าทับ (บาลานซ์/ม็อด)
game/
  core/content_db.gd     โหลด JSON ทั้งหมด, id แบบ "หมวด:ชื่อ"
  core/command_bus.gd    คิวคำสั่ง → validate → apply → history
  core/game_world.gd     สถานะโลกทั้งหมด + ลูป fixed-step (10 tick/วินาที)
  world/world_gen.gd     สร้างแผนที่: noise → ภูมิประเทศ, เมืองหลวง, แบ่งดินแดน
  economy/economy.gd     เงิน ทรัพยากร ก่อสร้าง คิวเกณฑ์ทหาร ตลาด
  military/army.gd       ทหารบก: เดินตาม A*, ยิงอัตโนมัติ, ยึดดินแดน
  military/strikes.gd    โดรน ขีปนาวุธ และระบบต่อต้านอากาศยาน
  diplomacy/diplomacy.gd สงคราม สันติภาพ พันธมิตร (พันธมิตรเข้าร่วมป้องกัน)
  ai/ai_bots.gd          AI ประเทศคู่แข่ง (ส่งคำสั่งแบบเดียวกับผู้เล่น)
  save/save_game.gd      เซฟ/โหลดทั้งสถานะ
world/
  map_view.gd            กล้อง อินพุต และกองเลเยอร์
  layers/                Ground, Territory, Buildings, Units, Fx, Overlay
ui/hud.gd                UI ทั้งหมด (สร้างด้วยโค้ด)
```

## เทียบกับพิมพ์เขียว

| ขั้นในพิมพ์เขียว | สถานะ | ไฟล์ |
|---|---|---|
| 1 แผนที่กริด + ประเทศ + สีดินแดน | ✅ | world_gen.gd, territory_layer.gd |
| 2 เงิน/ทรัพยากร + อาคารจาก JSON | ✅ | economy.gd, content_db.gd, content/ |
| 3 ผลิตยูนิต + เดิน/โจมตี + ยึดดินแดน | ✅ | army.gd |
| 4 AI ประเทศคู่แข่ง | ✅ | ai_bots.gd |
| 5 โดรน + ขีปนาวุธ + ต่อต้านอากาศยาน | ✅ | strikes.gd |
| 6 การทูต: สงคราม/สันติภาพ/พันธมิตร | ✅ | diplomacy.gd |
| 7 บันทึกเกม | ✅ | save_game.gd |
| 8 กองทัพเรือ รถไฟ การค้า ฤดูกาล ออนไลน์ | ยังไม่ทำ | ดูหัวข้อถัดไป |

## คำสั่งที่มีตอนนี้

ทุกปุ่มใน UI และทุกการตัดสินใจของ AI ส่งคำสั่งรูปแบบเดียวกัน:

```gdscript
world.submit(country_id, "mil.order_move", {"ids": [12, 13], "x": 40, "y": 22, "attack": true})
```

| คำสั่ง | args |
|---|---|
| `mil.build` | type, x, y |
| `mil.demolish` | id |
| `mil.order_move` | ids, x, y, attack |
| `mil.launch` | type (strike:DRONE / strike:MISSILE), x, y |
| `army.recruit` | type |
| `army.order_hold` / `army.disband` | ids |
| `econ.buy` / `econ.sell` | res, amount |
| `diplo.declare_war` / `diplo.propose_peace` / `diplo.propose_alliance` / `diplo.break_alliance` | target |
| `diplo.answer` | proposal, accept |

คำสั่งที่ผ่านการตรวจจะถูกเก็บใน `bus.history` (พร้อม tick) เป็นพื้นฐานสำหรับรีเพลย์และเล่นออนไลน์แบบ lockstep

## เพิ่มเนื้อหาใหม่

เพิ่มไฟล์ JSON ในโฟลเดอร์ที่ตรงหมวดแล้วเปิดเกมใหม่ ปุ่มใน UI จะโผล่เอง เช่นยูนิตใหม่:

```json
{ "id": "unit:MARINE", "name": "Marine", "icon": "M", "order": 4,
  "cost": {"money": 400, "food": 10}, "build_time": 6,
  "hp": 80, "attack": 10, "range": 1.2, "reload": 1.0, "speed": 1.1,
  "upkeep": {"money": 1, "food": 0.3}, "requires": "building:BARRACKS" }
```

อาคารที่มีฟิลด์ `"ad": {"range", "chance", "reload"}` จะทำหน้าที่ยิงสกัดอากาศยานโดยอัตโนมัติ
อาวุธในหมวด `strikes/` ต้องระบุ `launcher` เป็น id ของอาคารที่ใช้ยิง

## ขั้นต่อไปที่แนะนำ

- กองทัพเรือ: เพิ่มยูนิตที่เดินบนน้ำ (AStarGrid2D แยกอีกตัวสำหรับทะเล) + อาคารท่าเรือ
- รถไฟ/ถนน: ลดค่าน้ำหนักเส้นทางใน A* บนช่องที่มีราง
- ฤดูกาล: ตัวคูณความเร็ว/ผลผลิตตามวันในปี + shader เปลี่ยนสีพื้น
- หมอกสงคราม: เลเยอร์ใหม่ที่ซ่อนพื้นที่นอกระยะมองเห็น
- ออนไลน์: ส่ง `cmd` ผ่าน ENet/WebSocket ให้ทุกเครื่องรันที่ tick เดียวกัน (ต้องใช้ RNG ที่ seed เดียวกัน)
- ม็อดสคริปต์: เพิ่ม hook ให้ม็อดส่งคำสั่งผ่าน `CommandBus`
- แปลภาษา: ใช้ `tr()` + ไฟล์ `.po` และเพิ่มฟอนต์ที่รองรับภาษาไทย (ฟอนต์เริ่มต้นของ Godot ไม่มีอักษรไทย)
