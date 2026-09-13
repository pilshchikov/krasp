#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
asset_dir="ThirdParty/DPDFNet"
mkdir -p "$asset_dir"

# Pin both artifacts by checksum; never reuse a partial or changed download.
download() {
    local url="$1" destination="$2" checksum="$3"
    if [[ -f "$destination" ]] && [[ "$(shasum -a 256 "$destination" | cut -d ' ' -f 1)" == "$checksum" ]]; then
        return
    fi
    curl -fL --retry 3 "$url" -o "$destination.download"
    echo "$checksum  $destination.download" | shasum -a 256 -c -
    mv "$destination.download" "$destination"
}

archive="$asset_dir/sherpa-onnx-v1.13.8-universal2.tar.bz2"
download \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-universal2-shared-no-tts-lib.tar.bz2" \
    "$archive" "bdcc7c266d355697584dd4efb9dc766e45e18e87cec1fc553002a32cfcfab9a7"
download \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx" \
    "$asset_dir/dpdfnet2_48khz_hr.onnx" "0b399f8a58dc4d70d8cd97541f5c39869406145193b957d00a03b66070944928"

staging="$(mktemp -d "$asset_dir/.runtime-XXXXXX")"
trap 'rm -rf "$staging"' EXIT
tar -xjf "$archive" -C "$staging"
mkdir -p "$asset_dir/runtime"
for library in libsherpa-onnx-c-api.dylib libonnxruntime.dylib; do
    cp "$staging/sherpa-onnx-v1.13.8-osx-universal2-shared-no-tts-lib/lib/$library" "$asset_dir/runtime/$library"
done
install_name_tool -change @rpath/libonnxruntime.dylib @loader_path/libonnxruntime.dylib \
    "$asset_dir/runtime/libsherpa-onnx-c-api.dylib"
codesign --force --sign - "$asset_dir/runtime/libsherpa-onnx-c-api.dylib"
