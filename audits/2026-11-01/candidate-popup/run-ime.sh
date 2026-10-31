#!/bin/zsh
set -eu
IME_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$IME_AUDIT/../../.."
IME_SOURCE="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
IME_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
IME_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-search-audit}"
IME_OUTPUT="${1:?Usage: run-ime.sh output-directory}"
mkdir -p "$IME_OUTPUT"
IME_OUTPUT="$(cd "$IME_OUTPUT" && pwd)"
IME_PRODUCTS="$(swift build -c release --scratch-path "$IME_BUILD" --show-bin-path)"
mkdir -p "$IME_BUILD/audit-tools"
ditto "$IME_PRODUCTS/FluentKit_FluentKit.bundle" "$IME_BUILD/audit-tools/FluentKit_FluentKit.bundle"
IME_SOURCES=("$IME_SOURCE"/Sources/FluentIME/*.swift)
IME_SOURCES=( ${IME_SOURCES:#*/main.swift} )
shasum -a 256 "${IME_SOURCES[@]}" > "$IME_OUTPUT/app-source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -I "$IME_PRODUCTS" -I "$IME_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$IME_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${IME_SOURCES[@]}" "$IME_AUDIT/IMECandidateAudit.swift" \
    "$IME_PRODUCTS/FluentKit.o" "$IME_CORE/out/Products/Release/FluentIMECore.o" "$IME_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$IME_BUILD/audit-tools/IMECandidateAudit"
for IME_EXPANDED in 0 1; do
    mkdir -p "$IME_OUTPUT/expanded-$IME_EXPANDED"
    FLUENTIME_RENDER_THEME=dark FLUENTIME_RENDER_PAGE=keys FLUENTIME_RENDER_EXPANDED="$IME_EXPANDED" \
        "$IME_BUILD/audit-tools/IMECandidateAudit" "$IME_OUTPUT/expanded-$IME_EXPANDED/images" \
        "$IME_SOURCE/dist/Fluent IME.app/Contents/Resources/Rime" > "$IME_OUTPUT/expanded-$IME_EXPANDED/run.log" 2>&1
done
