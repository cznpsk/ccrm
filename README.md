# ccrm — resume/ลบ session ของ Claude Code, Codex, Kimi, Gemini

เลือก session เก่าจาก fzf แล้ว resume หรือลบได้เลย ไม่ต้องจำ session id

## ติดตั้ง / อัพเดท

ติดตั้งแล้วพิมพ์ `ccrm update` ได้เลย — ccrm เช็คเวอร์ชันใหม่จาก GitHub ให้อัตโนมัติ ถ้ามีจะขึ้นเตือนใน header

คำสั่งติดตั้งครั้งแรก (รันซ้ำ = อัพเดทเหมือนกัน):

### macOS / Linux (WSL)

```
curl -fsSL https://github.com/cznpsk/ccrm/releases/latest/download/install.sh | bash
```

ปิด terminal แล้วเปิดใหม่ (ครั้งแรกเท่านั้น PATH ถึงจะอัปเดต) พิมพ์ `ccrm`

install.sh จะลง `fzf` และ `jq` ให้อัตโนมัติผ่าน Homebrew (mac) หรือ apt (WSL/Linux) ถ้ายังไม่มี

### Windows (PowerShell)

```
irm https://github.com/cznpsk/ccrm/releases/latest/download/install.ps1 | iex
```

ปิด terminal แล้วเปิดใหม่ (ครั้งแรกเท่านั้น) พิมพ์ `ccrm`

install.ps1 จะลง `fzf` ให้อัตโนมัติผ่าน winget ถ้ายังไม่มี (ต้องมี winget ในเครื่อง — Windows 10/11 รุ่นใหม่มีติดมาอยู่แล้ว)

> ติดตั้งจาก zip แบบเดิมก็ยังได้: `./install.sh` หรือ `powershell -ExecutionPolicy Bypass -File .\install.ps1` ใน folder ที่แตก zip

## ข้อกำหนดเบื้องต้น

ต้องมี CLI ตัวใดตัวหนึ่งติดตั้งและ login ไว้แล้ว ถึงจะ resume session ของตัวนั้นได้:

- `claude` (Claude Code)
- `codex` (Codex CLI)
- `kimi` (Kimi Code CLI)
- `gemini` (Gemini CLI)

ไม่มีตัวไหนก็ไม่เป็นไร ccrm จะข้าม session ของตัวนั้นไปเฉยๆ

## วิธีใช้

```
ccrm          # ทุก session ทุก project (Claude/Codex/Kimi/Gemini)
ccrm update   # อัพเดทเป็นเวอร์ชันล่าสุด
```

คีย์ในหน้าจอเลือก session:

| คีย์ | ทำอะไร |
|---|---|
| พิมพ์อะไรก็ได้ | ค้นหา/กรอง session |
| ลูกศรขึ้นลง | เลื่อนเลือก |
| Enter | resume session ที่เลือก |
| Tab | เลือกจะลบ — กด Tab อีกครั้งบนบรรทัดเดิมเพื่อยืนยันลบ |
| Ctrl-A | รีเฟรชลิสต์ |
| Esc | ยกเลิก ไม่ทำอะไร |

## หมายเหตุ

- **Gemini**: ตัว CLI เองไม่รองรับ resume ด้วย session id ตรงๆ (`--resume` รับแค่ "latest" หรือเลขลำดับ) ccrm เลยใช้วิธี `cd` เข้า project เดิมก่อนแล้วโหลดไฟล์ session ตรงๆ แทน — ถ้า resume แล้ว error ผิดปกติ ลองเช็คว่า `gemini` CLI login/ใช้งานได้ปกติก่อน
- **Kimi**: ต้อง `cd` เข้า working directory เดิมของ session นั้นก่อน resume เสมอ (ข้อจำกัดของตัว CLI) ccrm จัดการให้อัตโนมัติแล้ว
- ลบ session แล้ว **กู้คืนไม่ได้** ระวังตอนกด Tab สองที
