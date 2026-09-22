#!/bin/bash
# 用法: ./rebuild_version.sh v1.1
TARGET=$1
WORKDIR="full-$TARGET"

if [ -z "$TARGET" ]; then
    echo "用法: ./rebuild_version.sh <版本号>"
    exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

for v in $(ls -d v*/ 2>/dev/null | sort -V); do
    if [[ "$v" > "$TARGET/" ]]; then break; fi
    echo "叠加 $v"
    cp -r "$v"* "$WORKDIR/" 2>/dev/null
done

echo "完整内容已重建到: $WORKDIR"