#!/usr/bin/env bash
# Сборка APK без Gradle: aapt -> javac -> dx -> zipalign -> apksigner.
# Требуются пакеты Ubuntu: aapt, dalvik-exchange, zipalign, apksigner,
# android-sdk-platform-23 и JDK.
set -euo pipefail

cd "$(dirname "$0")"
HERE="$(pwd)"

SDK="${ANDROID_SDK:-/usr/lib/android-sdk}"
ANDROID_JAR="$SDK/platforms/android-23/android.jar"
[ -f "$ANDROID_JAR" ] || ANDROID_JAR="/usr/share/java/com.android.android-23.jar"

BUILD="$HERE/build"
OUT="$HERE/dist"
APP="ege-trenazher-2026"

echo "==> Очистка"
rm -rf "$BUILD" "$OUT"
mkdir -p "$BUILD/gen" "$BUILD/obj" "$OUT"

echo "==> Генерация иконок"
( cd tools && java GenIcon.java "$HERE/res" )

echo "==> Генерация R.java (aapt)"
aapt package -f -m -J "$BUILD/gen" -M AndroidManifest.xml -S res -I "$ANDROID_JAR"

echo "==> Компиляция Java (javac, target 8)"
find src "$BUILD/gen" -name '*.java' > "$BUILD/sources.txt"
javac -source 8 -target 8 -encoding UTF-8 -nowarn \
      -classpath "$ANDROID_JAR" -d "$BUILD/obj" @"$BUILD/sources.txt" 2>/dev/null

echo "==> Дексирование (dx / dalvik-exchange)"
dalvik-exchange --dex --output="$BUILD/classes.dex" "$BUILD/obj"

echo "==> Упаковка ресурсов в APK (resources.arsc без сжатия)"
# -0 arsc: хранить resources.arsc без сжатия — требование Android 11+ при targetSdk>=30
aapt package -f -M AndroidManifest.xml -S res -I "$ANDROID_JAR" \
      -0 arsc -F "$BUILD/app.unaligned.apk"

echo "==> Добавление classes.dex"
( cd "$BUILD" && aapt add app.unaligned.apk classes.dex >/dev/null )

echo "==> Выравнивание (zipalign)"
zipalign -f 4 "$BUILD/app.unaligned.apk" "$BUILD/app.aligned.apk"

echo "==> Ключ для подписи"
KS="$BUILD/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -alias ege -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android \
    -dname "CN=EGE Trenazher, OU=Dev, O=Selkorin, C=RU" >/dev/null 2>&1
fi

echo "==> Подпись (apksigner)"
apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/$APP.apk" "$BUILD/app.aligned.apk"

echo "==> Проверка подписи"
apksigner verify --print-certs "$OUT/$APP.apk" >/dev/null && echo "Подпись OK"

echo ""
echo "Готово: $OUT/$APP.apk"
ls -lh "$OUT/$APP.apk"
