#!/bin/bash
# classify_and_diff.sh
# 用法: ./classify_and_diff.sh <Sprite目录> <新版本号>
# 示例: ./classify_and_diff.sh Sprite Ver1.37.5
# 作用: 仅按文件名判定重复。
#       Sprite/ 中任何文件，只要在最新 _full 的任意位置存在同名文件，
#       即视为重复并跳过；否则视为新增并按规则分类。
#       _full 中有但 Sprite/ 中没有的文件视为删除，
#       只把本次删除的文件放入 <新版本>/deleted/，不累积历史。
#       忽略 .gitkeep 和所有 xxx#xxx.png。
#       无删除则不建 deleted/；为空分类目录自动补 .gitkeep。

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

INCOMING="$1"
NEWVER="$2"

if [ -z "$INCOMING" ] || [ -z "$NEWVER" ]; then
    echo "用法: ./classify_and_diff.sh <Sprite目录> <新版本号>"
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

# 2. 创建新版本目录
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

# 4. 递归扫描基准目录，仅收集“主内容”里的文件名和相对路径
#    注意：跳过 deleted/ 目录，避免把历史删除文件当成基准
declare -A BASELINE_NAMES
declare -A BASELINE_RELPATH
while IFS= read -r f; do
    name="${f##*/}"
    [ "$name" = ".gitkeep" ] && continue
    [[ "$name" == *"#"*".png" ]] && continue
    BASELINE_NAMES["$name"]=1
    BASELINE_RELPATH["$name"]="${f#"$LATEST_FULL"/}"
done < <(find "$LATEST_FULL" -type f -not -path "*/deleted/*")

echo "基准文件名数: ${#BASELINE_NAMES[@]}"

# 5. 收集 Sprite/ 文件名
declare -A INCOMING_NAMES
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    name="${f##*/}"
    [ "$name" = ".gitkeep" ] && continue
    [[ "$name" == *"#"*".png" ]] && continue
    INCOMING_NAMES["$name"]=1
done

# 6. 处理新增
echo ""
echo "--- 处理新增 ---"
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    name="${f##*/}"

    [ "$name" = ".gitkeep" ] && continue
    if [[ "$name" == *"#"*".png" ]]; then
        echo "[忽略副本] $name"
        continue
    fi

    if [ -n "${BASELINE_NAMES[$name]}" ]; then
        continue
    fi

    target=$(classify "$name")
    cp "$f" "$NEWVER/$target/$name"
    BASELINE_NAMES["$name"]=1
    BASELINE_RELPATH["$name"]="$target/$name"
    echo "[新增] $name → $target/"
done

# 7. 处理删除：只把本次删除的文件放入 $NEWVER/deleted/
echo ""
echo "--- 处理删除 ---"
declare -A DELETED_FILES
for name in "${!BASELINE_NAMES[@]}"; do
    if [ -z "${INCOMING_NAMES[$name]}" ]; then
        DELETED_FILES["$name"]=1
    fi
done

if [ ${#DELETED_FILES[@]} -gt 0 ]; then
    for name in "${!DELETED_FILES[@]}"; do
        base_rel="${BASELINE_RELPATH[$name]}"
        base_sub="${base_rel%%/*}"
        case "$base_sub" in
            item_icon|status_icon|others) ;;
            *) base_sub=$(classify "$name") ;;
        esac
        mkdir -p "$NEWVER/deleted/$base_sub"
        cp "$LATEST_FULL/$base_rel" "$NEWVER/deleted/$base_sub/$name"
        echo "[删除] $name (原属 $base_sub)"
    done
    echo "删除文件已放入 $NEWVER/deleted/"
else
    echo "无删除文件，不创建 deleted/ 目录"
fi

# 8. 为空分类目录补 .gitkeep
echo ""
echo "--- 补齐空目录标记 ---"
for sub in item_icon status_icon others; do
    mkdir -p "$NEWVER/$sub"
    has_real=0
    for f in "$NEWVER/$sub"/*; do
        [ -e "$f" ] || continue
        fname="${f##*/}"
        if [ "$fname" != ".gitkeep" ]; then
            has_real=1
            break
        fi
    done
    if [ "$has_real" -eq 0 ]; then
        touch "$NEWVER/$sub/.gitkeep"
        echo "  $sub/ 为空，已补 .gitkeep"
    else
        if [ -f "$NEWVER/$sub/.gitkeep" ]; then
            rm -f "$NEWVER/$sub/.gitkeep"
            echo "  $sub/ 已有文件，移除 .gitkeep"
        fi
    fi
done

if [ -d "$NEWVER/deleted" ]; then
    for sub in item_icon status_icon others; do
        if [ -d "$NEWVER/deleted/$sub" ]; then
            has_real=0
            for f in "$NEWVER/deleted/$sub"/*; do
                [ -e "$f" ] || continue
                fname="${f##*/}"
                if [ "$fname" != ".gitkeep" ]; then
                    has_real=1
                    break
                fi
            done
            if [ "$has_real" -eq 0 ]; then
                touch "$NEWVER/deleted/$sub/.gitkeep"
            fi
        done
    done
fi

echo ""
echo "完成: 新增文件已分类到 $NEWVER/"