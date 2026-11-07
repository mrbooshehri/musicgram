#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

install=false
split=false
device_serial=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --split) split=true; shift ;;
    --install)
      install=true
      shift
      if [[ $# -gt 0 && $1 != -* ]]; then
        device_serial=$1
        shift
      fi
      ;;
    *) printf 'Usage: %s [--split] [--install [device-serial]]\n' "$0" >&2; exit 2 ;;
  esac
done

if $install; then
  if command -v adb >/dev/null 2>&1; then
    adb_command=$(command -v adb)
  else
    sdk_dir=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
    if [[ -z $sdk_dir && -f android/local.properties ]]; then
      sdk_dir=$(sed -n 's/^sdk\.dir=//p' android/local.properties | head -n 1)
    fi
    adb_command="$sdk_dir/platform-tools/adb"
    if [[ -z $sdk_dir || ! -x $adb_command ]]; then
      printf 'adb not found. Install Android platform-tools or set ANDROID_SDK_ROOT.\n' >&2
      exit 1
    fi
  fi
fi

read -rp 'Telegram API ID: ' telegram_api_id
read -rsp 'Telegram API hash: ' telegram_api_hash
printf '\n'
if [[ ! "$telegram_api_id" =~ ^[0-9]+$ ]] || [[ -z "$telegram_api_hash" ]]; then
  printf 'A numeric API ID and non-empty API hash are required.\n' >&2
  exit 1
fi
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
flutter pub get
build_args=()
if $split; then
  build_args=(--split-per-abi --target-platform android-arm64,android-x64)
fi
flutter build apk --release "${build_args[@]}" \
  "--dart-define=TELEGRAM_API_ID=$telegram_api_id" \
  "--dart-define=TELEGRAM_API_HASH=$telegram_api_hash"
apk_path=build/app/outputs/flutter-apk/app-release.apk
if $split; then
  printf '\nPhone APK: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk\n'
  printf 'x86-64 APK: build/app/outputs/flutter-apk/app-x86_64-release.apk\n'
else
  printf '\nAPK: %s\n' "$apk_path"
fi

if $install; then
  adb_args=()
  if [[ -n $device_serial ]]; then
    adb_args=(-s "$device_serial")
  fi
  if $split; then
    device_abis=$("$adb_command" "${adb_args[@]}" shell getprop ro.product.cpu.abilist | tr -d '\r')
    apk_path=''
    IFS=',' read -r -a supported_abis <<< "$device_abis"
    for abi in "${supported_abis[@]}"; do
      case $abi in
        arm64-v8a) apk_path=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk; break ;;
        x86_64) apk_path=build/app/outputs/flutter-apk/app-x86_64-release.apk; break ;;
      esac
    done
    if [[ -z $apk_path ]]; then
      printf 'No supported 64-bit APK for device ABIs: %s\n' "$device_abis" >&2
      exit 1
    fi
  fi
  printf 'Installing as an update (existing app data is retained)...\n'
  "$adb_command" "${adb_args[@]}" install -r "$apk_path"
fi
