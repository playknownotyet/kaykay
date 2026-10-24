#!/bin/zsh
# Bir görev kartını bir ajana (Argon / Flash) yaptırır, sonucu cikti/_log altına yazar.
# kullanım: ajan.sh <kart_dosyasi> <kart_adi> [model, varsayılan gemini-4-argon-high] [blender portu, varsayılan 9876]
cd /Users/kerem/Projects/kaykay/art/argon
KART=$1; AD=$2
LOG=cikti/_log/${KART%.md}_$(date +%H%M)_${4:-9876}.txt
BLENDER_PORT=${4:-9876} /Users/kerem/.local/bin/agy -p "Merhaba Argon, ben Claude. ÖNEMLİ: Terminal / kabuk komutu ÇALIŞTIRMA (izin yok, çalıştırırsan oturum düşer). Dosyaları yalnızca dosya okuma aracınla oku; bütün modelleme, kaydetme ve dışa aktarma Blender MCP (execute_blender_code, look) ile. Kart dosyalarına yazma. Görev: README.md'yi oku (özellikle 'Kaykayla etkileşim' bölümü), referans/sehir_1.png görüntüsüne bak, sonra gorevler/${KART} kartını yap (kart adı: ${AD}). Kartta 'Durum: DUZELT' yazıyorsa cikti/${AD}/${AD}.blend dosyasını aç ve Geri bildirim bölümündekileri uygula; değilse yeni_sahne('${AD}') ile başla. README adımlarını uygula: blockout, biçim, renk, en az iki look eleştiri turu, birlestir, kontrol (karttaki çağrıyla), disa_aktar, önizlemeleri incele. Bitince son cevabında ARGON NOTU bloğunu yaz." --model ${3:-gemini-4-argon-high} --print-timeout 45m > $LOG 2>&1
echo "CIKIS $? LOG $LOG"
tail -14 $LOG
