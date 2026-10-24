#!/bin/zsh
# kullanım: kuyruk.sh <port> <model> <kart.md:ad> [<kart.md:ad> ...]  — kartları sırayla yapar
PORT=$1; MODEL=$2; shift 2
for k in "$@"; do
  KART=${k%%:*}; AD=${k##*:}
  sed -i '' 's/^Durum: BEKLIYOR$/Durum: YAPILIYOR/' /Users/kerem/Projects/kaykay/art/argon/gorevler/$KART
  /Users/kerem/Projects/kaykay/tools/argon/ajan.sh $KART $AD $MODEL $PORT | head -1
  sed -i '' 's/^Durum: YAPILIYOR$/Durum: INCELENIYOR/' /Users/kerem/Projects/kaykay/art/argon/gorevler/$KART
done
echo "KUYRUK BITTI $PORT"
