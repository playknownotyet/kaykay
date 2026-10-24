#!/bin/zsh
# Kaykay çoklu ajan modelleme sistemini başlatır:
#  - 4 Blender penceresi açar (portlar 9876, 9877, 9878, 9879); her birinde MCP for Blender sunucusu
#    kendiliğinden başlar (tools/argon/blender_mcp_port.py)
#  - Mac'in uyumasını engeller (Blender'lar açık kaldıkça)
# Sonra Claude'a "ajanlar hazır" de; görevleri o dağıtır (tools/argon/kuyruk.sh).
B="/Users/kerem/Library/Application Support/Steam/steamapps/common/Blender/Blender.app/Contents/MacOS/Blender"
ADET=${1:-4}
for i in $(seq 0 $((ADET - 1))); do
  PORT=$((9876 + i))
  if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    echo "port $PORT zaten açık, atlandı"
    continue
  fi
  KK_MCP_PORT=$PORT "$B" --python /Users/kerem/Projects/kaykay/tools/argon/blender_mcp_port.py > /tmp/kaykay_blender_$PORT.log 2>&1 &
  echo "Blender açılıyor: port $PORT"
  sleep 2
done
# Blender'lar açık kaldıkça uyku yok
caffeinate -dimsu -w $(pgrep -n -f "Blender.app/Contents/MacOS/Blender") >/dev/null 2>&1 &
echo "Bekleniyor: MCP sunucuları..."
for t in $(seq 1 40); do
  N=$(lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | grep -cE "localhost:98(7[6-9])")
  [ "$N" -ge "$ADET" ] && break
  sleep 1
done
echo "Hazır: $N / $ADET Blender MCP sunucusu açık."
