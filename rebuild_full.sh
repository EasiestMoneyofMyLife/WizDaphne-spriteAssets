#!/bin/bash
# rebuild_full.sh
# 用法: ./rebuild_full.sh
# 作用: 将 old/ 与所有 Ver* 目录依次叠加，输出到 <最新版本>_full/
#       删除的文件会保留到输出目录的 deleted/<分类>/ 下，并生成 deleted_log.txt
#       删除日志仅记录第一次从结果中消失的版本，分类从前一版本检索
#       遍历时跳过 .gitkeep 和 xxx#xxx.png

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 1. 找出所有版本目录，按版本号排序
VERSIONS=($(ls -d Ver*/ 2>/dev/null | sed 's#/##' | sort -V))

if [ ${#VERSIONS[@]} -eq 0 ]; then
    echo "错误: 未找到任何 Ver* 版本目录"
    exit 1
fi

LATEST="${VERSIONS[-1]}"
OUTPUT="${LATEST}_full"

echo "最新版本: $LATEST"
echo "输出目录: $OUTPUT"

# 2. 清空并重建输出目录
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

# 3. 先叠加 old/
if [ -d "old" ]; then
    echo "叠加 old/"
    cp -r old/. "$OUTPUT/"
    find "$OUTPUT" -name ".gitkeep" -delete
fi

# 4. 删除状态表：deleted_record[文件名]="分类|删除起始版本"
declare -A DELETED_RECORD

# 5. 依次叠加每个版本
for v in "${VERSIONS[@]}"; do
    echo "叠加 $v/"

    # 5a. 复制该版本的新增/修改文件
    for sub in item_icon status_icon others; do
        if [ -d "$v/$sub" ]; then
            mkdir -p "$OUTPUT/$sub"
            for f in "$v/$sub"/*; do
                [ -e "$f" ] || continue
                name="${f##*/}"
                [ "$name" = ".gitkeep" ] && continue
                [[ "$name" == *"#"*".png" ]] && continue
                cp "$f" "$OUTPUT/$sub/$name"
                # 若该文件之前被删除过，现在又出现，说明它被恢复了
                if [ -n "${DELETED_RECORD[$name]}" ]; then
                    echo "  [恢复] $name (曾于 ${DELETED_RECORD[$name]#*|} 删除)"
                    unset DELETED_RECORD["$name"]
                fi
            done
        fi
    done

    # 5b. 处理 deleted/：先检索分类，再把文件保留到输出目录的 deleted/，然后删除
    if [ -d "$v/deleted" ]; then
        for sub in item_icon status_icon others; do
            if [ -d "$v/deleted/$sub" ]; then
                for f in "$v/deleted/$sub"/*; do
                    [ -e "$f" ] || continue
                    name="${f##*/}"
                    [ "$name" = ".gitkeep" ] && continue
                    [[ "$name" == *"#"*".png" ]] && continue

                    # 从当前完整状态（删除前一个版本）检索分类
                    found_sub="unknown"
                    for s in item_icon status_icon others; do
                        if [ -f "$OUTPUT/$s/$name" ]; then
                            found_sub="$s"
                            break
                        fi
                    done

                    # 保留一份到输出目录的 deleted/ 下
                    mkdir -p "$OUTPUT/deleted/$found_sub"
                    cp "$OUTPUT/$found_sub/$name" "$OUTPUT/deleted/$found_sub/$name" 2>/dev/null || true

                    # 从主内容中删除
                    rm -f "$OUTPUT/item_icon/$name" "$OUTPUT/status_icon/$name" "$OUTPUT/others/$name"

                    # 仅记录第一次消失的版本
                    if [ -z "${DELETED_RECORD[$name]}" ]; then
                        DELETED_RECORD["$name"]="$found_sub|$v"
                    fi
                done
            fi
        done
    fi
done

# 6. 清理输出目录主内容里残留的 .gitkeep（保留 deleted/ 下的）
find "$OUTPUT/item_icon" "$OUTPUT/status_icon" "$OUTPUT/others" -name ".gitkeep" -delete 2>/dev/null || true

# 7. 生成删除日志
if [ ${#DELETED_RECORD[@]} -gt 0 ]; then
    mkdir -p "$OUTPUT/deleted"
    LOG="$OUTPUT/deleted/deleted_log.txt"
    echo "# 删除记录" > "$LOG"
    echo "# 格式: 文件名 | 分类 | 第一次消失的版本" >> "$LOG"
    echo "" >> "$LOG"

    for name in $(echo "${!DELETED_RECORD[@]}" | tr ' ' '\n' | sort); do
        info="${DELETED_RECORD[$name]}"
        sub="${info%%|*}"
        ver="${info##*|}"
        echo "$name | $sub | $ver" >> "$LOG"
    done

    echo "已生成删除日志: $LOG"
else
    echo "无删除文件，不生成 deleted/ 目录"
fi

echo "完成: 完整内容已重建到 $OUTPUT/"