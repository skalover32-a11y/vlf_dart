#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SING_BOX_DIR="$ROOT_DIR/sing-box"
OUT_DIR="$ROOT_DIR/android/app/libs"
AAR_NAME="libbox.aar"
AAR_PATH="$SING_BOX_DIR/$AAR_NAME"
LIB_DEST="$OUT_DIR/$AAR_NAME"

if [[ ! -d "$SING_BOX_DIR" ]]; then
  echo "[build_libbox_android] sing-box sources not found at $SING_BOX_DIR" >&2
  exit 1
fi

if [[ ! -d "$SING_BOX_DIR/cmd/internal/build_libbox" ]]; then
  echo "[build_libbox_android] cmd/internal/build_libbox not found inside sing-box." >&2
  echo "Update the submodule or adjust the path." >&2
  exit 1
fi

if ! command -v gomobile >/dev/null 2>&1; then
  echo "[build_libbox_android] gomobile is not available in PATH.\n" \
       "Install it via 'go install golang.org/x/mobile/cmd/gomobile@latest' and run 'gomobile init'." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$AAR_PATH"

pushd "$SING_BOX_DIR" >/dev/null
GO111MODULE=on go run ./cmd/internal/build_libbox -target android -platform android/arm64
popd >/dev/null

if [[ ! -f "$AAR_PATH" ]]; then
  echo "[build_libbox_android] Expected $AAR_PATH but it was not produced" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp "$AAR_PATH" "$LIB_DEST"
chmod 644 "$LIB_DEST"

echo "[build_libbox_android] Copied $AAR_NAME to $LIB_DEST"
