#!/usr/bin/env bash
# iOS dağıtım sertifikası yardımcısı. Windows'ta Git Bash ile çalışır, Mac gerekmez.
#
#   bash tools/ios_sertifika.sh csr                         -> Apple'a yüklenecek CSR dosyası
#   bash tools/ios_sertifika.sh p12 <indirilen .cer>        -> .p12 + GitHub secret metni
#   bash tools/ios_sertifika.sh profil <indirilen .mobileprovision> -> GitHub secret metni
#
# Tüm dosyalar depo DIŞINDA, kullanıcı klasöründeki "kaykay-ios-imza" içinde durur.
# Bu klasörü kimseyle paylaşma ve yedekle: özel anahtar kaybolursa sertifika yeniden yapılmalı.
# Ayrıntılı anlatım: docs/IOS_KURULUM.md

set -euo pipefail
# Git Bash, "/CN=..." konusunu dosya yolu sanıp bozmasın.
export MSYS2_ARG_CONV_EXCL="/CN="

DIR="$HOME/kaykay-ios-imza"
KEY="$DIR/ios_dagitim.key"
mkdir -p "$DIR"

klasoru_ac() {
	if command -v explorer.exe > /dev/null 2>&1; then
		explorer.exe "$(cygpath -w "$DIR")" || true
	fi
}

case "${1:-}" in
	csr)
		if [ -f "$KEY" ]; then
			echo "Zaten bir özel anahtar var: $KEY"
			echo "Yeni bir tane istiyorsan önce o dosyayı başka yere taşı."
			exit 1
		fi
		openssl genrsa -out "$KEY" 2048 2> /dev/null
		openssl req -new -key "$KEY" -out "$DIR/ios_dagitim.csr" -subj "/CN=Kaykay iOS Dagitim/C=TR"
		echo
		echo "Tamam. Apple'a yükleyeceğin dosya:"
		echo "  $DIR/ios_dagitim.csr"
		klasoru_ac
		;;

	p12)
		CER="${2:-}"
		if [ -z "$CER" ] || [ ! -f "$CER" ]; then
			echo "Kullanım: bash tools/ios_sertifika.sh p12 <Apple'dan indirilen distribution.cer yolu>"
			exit 1
		fi
		if [ ! -f "$KEY" ]; then
			echo "Özel anahtar bulunamadı ($KEY). Önce 'csr' adımını çalıştır."
			exit 1
		fi
		openssl x509 -inform DER -in "$CER" -out "$DIR/ios_dagitim.pem" 2> /dev/null \
			|| openssl x509 -in "$CER" -out "$DIR/ios_dagitim.pem"
		if [ "$(openssl x509 -noout -modulus -in "$DIR/ios_dagitim.pem")" != "$(openssl rsa -noout -modulus -in "$KEY" 2> /dev/null)" ]; then
			echo "Bu .cer dosyası bu bilgisayardaki CSR ile yapılmamış. Doğru dosyayı seçtiğinden emin ol."
			exit 1
		fi
		while true; do
			read -r -s -p "p12 için bir şifre belirle (ekranda görünmez): " P12PASS; echo
			read -r -s -p "Şifreyi tekrar yaz: " P12PASS2; echo
			if [ -n "$P12PASS" ] && [ "$P12PASS" = "$P12PASS2" ]; then
				break
			fi
			echo "Şifreler boş ya da birbirini tutmuyor, tekrar dene."
		done
		export P12PASS
		# 3DES/SHA1: macOS anahtar zinciri yeni OpenSSL varsayılanlarını okuyamıyor.
		openssl pkcs12 -export -inkey "$KEY" -in "$DIR/ios_dagitim.pem" \
			-name "Kaykay iOS Dagitim" -out "$DIR/ios_dagitim.p12" -passout env:P12PASS \
			-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
		base64 -w0 "$DIR/ios_dagitim.p12" > "$DIR/IOS_DIST_CERT_P12_BASE64.txt"
		echo
		echo "Tamam. GitHub secret'ları:"
		echo "  IOS_DIST_CERT_P12_BASE64 -> $DIR/IOS_DIST_CERT_P12_BASE64.txt dosyasının içeriği"
		echo "  IOS_DIST_CERT_PASSWORD   -> az önce belirlediğin şifre"
		klasoru_ac
		;;

	profil)
		PROFILE="${2:-}"
		if [ -z "$PROFILE" ] || [ ! -f "$PROFILE" ]; then
			echo "Kullanım: bash tools/ios_sertifika.sh profil <indirilen .mobileprovision yolu>"
			exit 1
		fi
		base64 -w0 "$PROFILE" > "$DIR/IOS_PROVISIONING_PROFILE_BASE64.txt"
		echo "Tamam. GitHub secret'ı:"
		echo "  IOS_PROVISIONING_PROFILE_BASE64 -> $DIR/IOS_PROVISIONING_PROFILE_BASE64.txt dosyasının içeriği"
		klasoru_ac
		;;

	*)
		sed -n '2,10p' "$0"
		exit 1
		;;
esac
