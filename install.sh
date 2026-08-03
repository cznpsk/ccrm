#!/usr/bin/env bash
# ติดตั้ง ccrm — รองรับ macOS และ Linux/WSL
set -euo pipefail

os="$(uname)"
raw="https://raw.githubusercontent.com/cznpsk/ccrm/main"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-/nonexistent}")" 2>/dev/null && pwd || true)"

install_dep() {
  local cmd="$1" pkg="$2"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  echo "ติดตั้ง $cmd ..."
  if [[ "$os" == "Darwin" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "ต้องมี Homebrew ก่อน: https://brew.sh"
      exit 1
    fi
    brew install "$pkg"
  else
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

install_dep fzf fzf
install_dep jq jq

mkdir -p "$HOME/.local/bin"
if [[ -n "$script_dir" && -f "$script_dir/ccrm" ]]; then
  cp "$script_dir/ccrm" "$HOME/.local/bin/ccrm"
else
  curl -fsSL "$raw/ccrm" -o "$HOME/.local/bin/ccrm"
fi
chmod +x "$HOME/.local/bin/ccrm"
echo "ติดตั้ง ccrm ไปที่ ~/.local/bin/ccrm แล้ว"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo ""
    echo "หมายเหตุ: ~/.local/bin ยังไม่อยู่ใน PATH เพิ่มบรรทัดนี้ใน ~/.bashrc หรือ ~/.zshrc:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
    echo "แล้วเปิด terminal ใหม่"
    ;;
esac

echo ""
for c in claude codex; do
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "หมายเหตุ: ยังไม่มี $c CLI ในเครื่องนี้ — ต้องติดตั้งแยกเองก่อนใช้ ccrm resume $c session"
  fi
done

echo ""
echo "ติดตั้งเสร็จ — พิมพ์ ccrm เพื่อใช้งาน (ccrm -a ดูทุก project)"
