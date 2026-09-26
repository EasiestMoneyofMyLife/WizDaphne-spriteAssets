#!/bin/bash
# classify_and_diff.sh
# 用法: ./classify_and_diff.sh <待分类目录> <新版本号>
# 示例: ./classify_and_diff.sh incoming Ver1.37.5
# 作用: 将 incoming/ 下的图标与最新 _full 对比，
#       新增/修改文件分类到 <新版本>/ 下；
#       删除文件放入 <新版本>/deleted/；
#       忽略所有 xxx#xxx.png；无删除则不建 deleted/

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

INCOMING="$1"
NEWVER="$2"

if [ -z "$INCOMING" ] || [ -z "$NEWVER" ]; then
    echo "用法: ./classify_and_diff.sh <待分类目录> <新版本号>"
    exit 1
fi

if [ ! -d "$INCOMING" ]; then
    echo "错误: 目录不存在: $INCOMING"
    exit 1
fi

# 1. 找出最新的 _full 目录
LATEST_FULL=$(ls -d Ver*_full/ 2>/dev/null | sed 's#/##' | sort -V | tail -n 1)

if [ -z "$LATEST_FULL" ]; then
    echo "错误: 未找到任何 *_full 目录，请先运行 rebuild_full.sh"
    exit 1
fi

echo "对比基准: $LATEST_FULL"
echo "新版本:   $NEWVER"
echo "待分类:   $INCOMING"

# 2. 创建新版本目录（deleted 按需创建）
mkdir -p "$NEWVER/item_icon" "$NEWVER/status_icon" "$NEWVER/others"

# 3. 分类函数
classify() {
    local name="$1"
    if [ "$name" = "monster_bird_egg.png" ] || [ "$name" = "monster_bird_nest.png" ]; then
        echo "item_icon"; return
    fi
    if [[ "$name" == item_icon_*.png ]]; then
        echo "item_icon"; return
    fi
    if [[ "$name" == status_icon_*.png ]]; then
        echo "status_icon"; return
    fi
    if [[ "$name" == samurai_*.png ]]; then
        echo "status_icon"; return
    fi
    echo "others"
}

# 4. 收集基准文件（按文件名索引），忽略含 # 的副本
declare -A BASELINE
for sub in item_icon status_icon others; do
    if [ -d "$LATEST_FULL/$sub" ]; then
        for f in "$LATEST_FULL/$sub"/*; do
            [ -e "$f" ] || continue
            name=$(basename "$f")
            if [[ "$name" == *"#"*".png" ]]; then
                continue
            fi
            BASELINE["$name"]="$sub"
        done
    fi
done

# 5. 处理新增/修改（忽略含 # 的文件）
echo ""
echo "--- 处理新增/修改 ---"
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")

    if [[ "$name" == *"#"*".png" ]]; then
        echo "[忽略副本] $name"
        continue
    fi

    old_sub="${BASELINE[$name]}"
    need_copy=0
    if [ -z "$old_sub" ]; then
        need_copy=1
        echo "[新增] $name"
    else
        if ! cmp -s "$f" "$LATEST_FULL/$old_sub/$name"; then
            need_copy=1
            echo "[修改] $name"
        fi
    fi

    if [ $need_copy -eq 1 ]; then
        target=$(classify "$name")
        cp "$f" "$NEWVER/$target/$name"
        BASELINE["$name"]="$target"
    fi
done

# 6. 处理删除：基准里有、incoming 里没有的
echo ""
echo "--- 处理删除 ---"
declare -A DELETED_FILES
for name in "${!BASELINE[@]}"; do
    if [ ! -e "$INCOMING/$name" ]; then
        old_sub="${BASELINE[$name]}"
        DELETED_FILES["$name"]="$old_sub"
    fi
done

if [ ${#DELETED_FILES[@]} -gt 0 ]; then
    for name in "${!DELETED_FILES[@]}"; do
        old_sub="${DELETED_FILES[$name]}"
        mkdir -p "$NEWVER/deleted/$old_sub"
        cp "$LATEST_FULL/$old_sub/$name" "$NEWVER/deleted/$old_sub/$name"
        echo "[删除] $name (原属 $old_sub)"
    done
    echo "删除文件已放入 $NEWVER/deleted/"
else
    echo "无删除文件，不创建 deleted/ 目录"
fi

echo ""
echo "完成: 新增/修改已分类到 $NEWVER/"