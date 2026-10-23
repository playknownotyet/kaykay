#!/bin/zsh
# Paralel ajanlar için ek Blender pencereleri: her biri MCP sunucusunu kendi portunda başlatır.
# Kullanım: zsh tools/argon/paralel_blender.sh [adet]   (varsayılan 3: portlar 9877, 9878, 9879)
B="/Users/kerem/Library/Application Support/Steam/steamapps/common/Blender/Blender.app/Contents/MacOS/Blender"
ADET=${1:-3}
for i in $(seq 1 $ADET); do
  PORT=$((9876 + i))
  KK_MCP_PORT=$PORT "$B" --python /Users/kerem/Projects/kaykay/tools/argon/blender_mcp_port.py > /tmp/kaykay_blender_$PORT.log 2>&1 &
  echo "Blender açılıyor: port $PORT"
  sleep 2
done
echo "Pencereler açılınca MCP sunucuları birkaç saniye içinde kendiliğinden başlar."
