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

## ล็อก/เข้ารหัส session (macOS + Windows)

เก็บ session + login ของ Claude, Codex, Kimi, Gemini ไว้ในดิสก์อิมเมจเข้ารหัส AES-256 ล็อกแล้วอ่านไม่ได้ถ้าไม่มีรหัส

```
ccrm lock-setup    # ตั้งค่าครั้งแรก: ตั้งรหัสผ่าน → ย้ายข้อมูลเข้าวอลต์ → ล็อกอัตโนมัติตอน sleep
ccrm lock          # ล็อก (หรือ claude-lock, หรือ Ctrl-L ในหน้า ccrm)
ccrm unlock        # ปลดล็อก (หรือ claude-unlock, หรือแค่เปิด ccrm จะถามรหัสเอง)
ccrm lock-status   # ดูสถานะ
ccrm lock-auto off # ปิดล็อกอัตโนมัติตอน sleep (on = เปิด)
ccrm lock-cleanup  # ลบข้อมูลเดิมแบบไม่เข้ารหัสหลังย้าย (ทำหลังลองใช้แล้วว่าปกติ)
```

- รัน `lock-setup` จาก terminal ปกติ และปิด claude/codex/kimi/gemini ให้หมดก่อน
- **ลืมรหัสผ่าน = ข้อมูลหายถาวร** ไม่มีทางกู้
- ตอนเครื่อง sleep (ปิดฝา) ccrm จะปิด AI CLI ที่เปิดค้างให้แล้วล็อก — terminal ที่ `cd` ค้างอยู่ใน `~/.claude` จะทำให้ล็อกไม่ได้ (ขึ้นแจ้งเตือน)
- ตอนล็อก `~/.claude` เป็นโฟลเดอร์ว่างที่เขียนไม่ได้ เปิด `claude` ตรงๆ จะ error — ปลดล็อกก่อน
- `kimi` ติดตั้งอยู่ใน `~/.kimi-code/bin` เลยใช้ไม่ได้ตอนล็อก (ปกติ)
- ล็อกอัตโนมัติใช้ `sleepwatcher` (ติดตั้งผ่าน Homebrew ให้เอง)
- **Windows** ใช้คำสั่งเดียวกันทั้งหมด — `lock-setup` ติดตั้ง VeraCrypt ให้เอง (ดาวน์โหลด MSI จากผู้ผลิต ตรวจลายเซ็น IDRIX, มีหน้าต่างขอสิทธิ์ admin ครั้งเดียว รองรับ ARM64) แล้วสร้างคอนเทนเนอร์ AES ที่ `%LOCALAPPDATA%\ccrm\vault.hc` (ไฟล์โตตามข้อมูลจริง) mount เป็นไดรฟ์ + junction `~\.claude` `~\.codex` `~\.kimi-code` `~\.gemini` เข้าไป
- Windows ตั้ง `CLAUDE_CONFIG_DIR` ให้ `.claude.json` ไปอยู่ในวอลต์ — เปิด terminal ใหม่หลัง setup
- Windows ล็อกอัตโนมัติตอน sleep ผ่าน Task Scheduler (`ccrm-sleeplock`)

## หมายเหตุ

- **Gemini**: ตัว CLI เองไม่รองรับ resume ด้วย session id ตรงๆ (`--resume` รับแค่ "latest" หรือเลขลำดับ) ccrm เลยใช้วิธี `cd` เข้า project เดิมก่อนแล้วโหลดไฟล์ session ตรงๆ แทน — ถ้า resume แล้ว error ผิดปกติ ลองเช็คว่า `gemini` CLI login/ใช้งานได้ปกติก่อน
- **Kimi**: ต้อง `cd` เข้า working directory เดิมของ session นั้นก่อน resume เสมอ (ข้อจำกัดของตัว CLI) ccrm จัดการให้อัตโนมัติแล้ว
- ลบ session แล้ว **กู้คืนไม่ได้** ระวังตอนกด Tab สองที
