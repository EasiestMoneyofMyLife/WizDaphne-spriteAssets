#!/bin/bash
# rebuild_full.sh
# 用法: ./rebuild_full.sh [目标版本号]
# 示例: ./rebuild_full.sh Ver1.37.5
# 作用: 将 Old/ 与所有 Ver* 目录依次叠加，输出到 <目标版本>_full/
#       若未传目标版本，则使用仓库中版本号最大的版本
#       变更/删除的旧图统一保留在输出目录的 diff/ 下：
#         diff/changed/<分类>/  被覆盖的旧图（最近一次覆盖前）
#         diff/deleted/<分类>/  被删除的旧图
#       并生成 diff/changed_log.txt 与 diff/deleted_log.txt
#       遍历时跳过 .gitkeep、xxx#xxx.png，以及所有 *_full 目录

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 1. 找出所有版本目录，按版本号排序
VERSIONS=($(ls -d Ver*/ 2>/dev/null | sed 's#/##' | grep -v '_full$' | sort -V))

if [ ${#VERSIONS[@]} -eq 0 ]; then
    echo "错误: 未找到任何 Ver* 版本目录"
    exit 1
fi

# 2. 决定目标版本
if [ -n "$1" ]; then
    TARGET_VER="$1"
    if [ ! -d "$TARGET_VER" ]; then
        echo "错误: 版本目录不存在: $TARGET_VER"
        exit 1
    fi
    if [[ "$TARGET_VER" == *_full ]]; then
        echo "错误: 目标版本不能是 _full 目录: $TARGET_VER"
        exit 1
    fi
else
    TARGET_VER="${VERSIONS[-1]}"
fi

OUTPUT="${TARGET_VER}_full"

echo "目标版本: $TARGET_VER"
echo "输出目录: $OUTPUT"

# 3. 清空并重建输出目录
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

# 4. 先叠加 Old/
if [ -d "Old" ]; then
    echo "叠加 Old/"
    cp -r Old/. "$OUTPUT/"
    find "$OUTPUT" -name ".gitkeep" -delete
else
    echo "警告: Old/ 目录不存在，跳过"
fi

# 5. 状态表
declare -A DELETED_RECORD
CHANGED_LOG=()
DELETED_LOG=()

# 6. 依次叠加每个版本，直到目标版本
for v in "${VERSIONS[@]}"; do
    if [[ "$v" > "$TARGET_VER" ]]; then
        break
    fi

    echo "叠加 $v/"

    # 6a. 复制该版本的新增/修改文件
    for sub in item_icon status_icon others; do
        if [ -d "$v/$sub" ]; then
            mkdir -p "$OUTPUT/$sub"
            for f in "$v/$sub"/*; do
                [ -e "$f" ] || continue
                name="${f##*/}"
                [ "$name" = ".gitkeep" ] && continue
                [[ "$name" == *"#"*".png" ]] && continue

                existing=""
                for s in item_icon status_icon others; do
                    if [ -f "$OUTPUT/$s/$name" ]; then
                        existing="$s"
                        break
                    fi
                done
                if [ -n "$existing" ]; then
                    mkdir -p "$OUTPUT/diff/changed/$existing"
                    cp "$OUTPUT/$existing/$name" "$OUTPUT/diff/changed/$existing/$name"
                    CHANGED_LOG+=("$name | $existing | $v")
                    cp "$f" "$OUTPUT/$sub/$name"
                    if [ "$existing" != "$sub" ]; then
                        rm -f "$OUTPUT/$existing/$name"
                    fi
                else
                    cp "$f" "$OUTPUT/$sub/$name"
                fi

                if [ -n "${DELETED_RECORD[$name]}" ]; then
                    echo "  [恢复] $name (曾于 ${DELETED_RECORD[$name]#*|} 删除)"
                    unset DELETED_RECORD["$name"]
                fi
            done
        fi
    done

    # 6b. 处理 deleted/：旧图保留到 diff/deleted/，然后删除
    if [ -d "$v/deleted" ]; then
        for sub in item_icon status_icon others; do
            if [ -d "$v/deleted/$sub" ]; then
                for f in "$v/deleted/$sub"/*; do
                    [ -e "$f" ] || continue
                    name="${f##*/}"
                    [ "$name" = ".gitkeep" ] && continue
                    [[ "$name" == *"#"*".png" ]] && continue

                    found_sub="unknown"
                    for s in item_icon status_icon others; do
                        if [ -f "$OUTPUT/$s/$name" ]; then
                            found_sub="$s"
                            break
                        fi
                    done

                    if [ -f "$OUTPUT/$found_sub/$name" ]; then
                        mkdir -p "$OUTPUT/diff/deleted/$found_sub"
                        cp "$OUTPUT/$found_sub/$name" "$OUTPUT/diff/deleted/$found_sub/$name"
                        DELETED_LOG+=("$name | $found_sub | $v")
                    else
                        echo "  [警告] 删除文件在完整状态中不存在: $name (分类: $found_sub)"
                        DELETED_LOG+=("$name | $found_sub | $v")
                    fi

                    rm -f "$OUTPUT/item_icon/$name" "$OUTPUT/status_icon/$name" "$OUTPUT/others/$name"

                    if [ -z "${DELETED_RECORD[$name]}" ]; then
                        DELETED_RECORD["$name"]="$found_sub|$v"
                    fi
                done
            fi
        done
    fi
done

# 7. 清理主内容里残留的 .gitkeep（保留 diff/ 下的）
find "$OUTPUT/item_icon" "$OUTPUT/status_icon" "$OUTPUT/others" -name ".gitkeep" -delete 2>/dev/null || true

# 8. 生成日志
if [ ${#CHANGED_LOG[@]} -gt 0 ] || [ ${#DELETED_RECORD[@]} -gt 0 ]; then
    mkdir -p "$OUTPUT/diff"

    if [ ${#CHANGED_LOG[@]} -gt 0 ]; then
        LOG="$OUTPUT/diff/changed_log.txt"
        echo "# 变更记录（旧图保存在 diff/changed/<分类>/）" > "$LOG"
        echo "# 格式: 文件名 | 分类 | 发生覆盖的版本" >> "$LOG"
        echo "" >> "$LOG"
        for line in "${CHANGED_LOG[@]}"; do
            echo "$line" >> "$LOG"
        done
        echo "已生成变更日志: $LOG"
    fi

    if [ ${#DELETED_RECORD[@]} -gt 0 ]; then
        LOG="$OUTPUT/diff/deleted_log.txt"
        echo "# 删除记录（旧图保存在 diff/deleted/<分类>/）" > "$LOG"
        echo "# 格式: 文件名 | 分类 | 第一次消失的版本" >> "$LOG"
        echo "" >> "$LOG"
        for name in $(echo "${!DELETED_RECORD[@]}" | tr ' ' '\n' | sort); do
            info="${DELETED_RECORD[$name]}"
            sub="${info%%|*}"
            ver="${info##*|}"
            echo "$name | $sub | $ver" >> "$LOG"
        done
        echo "已生成删除日志: $LOG"
    fi
else
    echo "无变更/删除文件，不生成 diff/ 目录"
fi

echo "完成: 完整内容已重建到 $OUTPUT/"