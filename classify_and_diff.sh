#!/bin/bash
# classify_and_diff.sh
# 用法: ./classify_and_diff.sh <Sprite目录> <新版本号>
#
# 规则:
#   1) 文件名首次出现 -> 直接新增，不比对
#   2) 文件名已存在   -> dHash 比对:
#        distance <= SAME_THRESHOLD -> 重复，跳过
#        distance >  SAME_THRESHOLD -> 变更:
#            新图 -> 根目录分类文件夹
#            旧图 -> diff/changed/<分类>/
#   3) 基准有、Sprite 没有 -> 删除，旧图放入 diff/deleted/<分类>/
#   仅输出本次运行的差异，不生成任何 log，不累积历史。
#   忽略 .gitkeep 和所有 *"#"*.png

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

# ============ 配置 ============
USE_DHASH="${USE_DHASH:-1}"
SAME_THRESHOLD="${SAME_THRESHOLD:-5}"
DHASH_BATCH="$ROOT/dhash_batch.py"

# ============ 选择 Python ============
PY="${PYTHON_BIN:-}"
if [ -z "$PY" ]; then
    if [ -x "$ROOT/venv/Scripts/python.exe" ]; then
        PY="$ROOT/venv/Scripts/python.exe"
    elif [ -x "$ROOT/venv/Scripts/python" ]; then
        PY="$ROOT/venv/Scripts/python"
    elif [ -x "$ROOT/venv/bin/python" ]; then
        PY="$ROOT/venv/bin/python"
    elif command -v python >/dev/null 2>&1; then
        PY="python"
    elif command -v python3 >/dev/null 2>&1; then
        PY="python3"
    fi
fi

if [ -z "$PY" ] || [ ! -f "$DHASH_BATCH" ]; then
    if [ "$USE_DHASH" = "1" ]; then
        echo "警告: Python 或 dhash_batch.py 缺失，自动关闭 dHash"
        USE_DHASH=0
    fi
elif ! "$PY" -c "import PIL" >/dev/null 2>&1; then
    if [ "$USE_DHASH" = "1" ]; then
        echo "警告: 当前 Python 无法导入 Pillow，自动关闭 dHash"
        echo "       修复: \"$PY\" -m pip install Pillow"
        USE_DHASH=0
    fi
fi

# ============ 1. 找最新 _full ============
LATEST_FULL=$(ls -d Ver*_full/ 2>/dev/null | sed 's#/##' | sort -V | tail -n 1)
if [ -z "$LATEST_FULL" ]; then
    echo "错误: 未找到任何 *_full 目录"
    exit 1
fi

echo "对比基准: $LATEST_FULL"
echo "新版本:   $NEWVER"
echo "待分类:   $INCOMING"
if [ -n "$PY" ]; then echo "Python:   $PY"; else echo "Python:   未找到"; fi
if [ "$USE_DHASH" = "1" ]; then
    echo "dHash:    启用 (同名阈值=$SAME_THRESHOLD)"
else
    echo "dHash:    禁用"
fi

# ============ 2. 创建目录 ============
mkdir -p "$NEWVER/item_icon" "$NEWVER/status_icon" "$NEWVER/others"

# ============ 3. 分类函数 ============
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

# ============ 4. 扫描基准（排除 diff/） ============
declare -A BASELINE_NAMES
declare -A BASELINE_RELPATH
while IFS= read -r f; do
    name="${f##*/}"
    [ "$name" = ".gitkeep" ] && continue
    [[ "$name" == *"#"*".png" ]] && continue
    BASELINE_NAMES["$name"]=1
    BASELINE_RELPATH["$name"]="${f#"$LATEST_FULL"/}"
done < <(find "$LATEST_FULL" -type f -not -path "*/diff/*" -not -path "*/deleted/*")
echo "基准文件名数: ${#BASELINE_NAMES[@]}"

# ============ 5. 收集 Sprite 文件名 ============
declare -A INCOMING_NAMES
for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    name="${f##*/}"
    [ "$name" = ".gitkeep" ] && continue
    [[ "$name" == *"#"*".png" ]] && continue
    INCOMING_NAMES["$name"]=1
done

# ============ 6. 只对同名文件计算 dHash ============
TMP_BASE_TSV="$ROOT/.dhash_base.tsv"
TMP_CAND_TSV="$ROOT/.dhash_cand.tsv"
TMP_SAME_TSV="$ROOT/.dhash_same.tsv"
declare -A SAME_DIST

if [ "$USE_DHASH" = "1" ]; then
    same_count=0
    for name in "${!INCOMING_NAMES[@]}"; do
        if [ -n "${BASELINE_NAMES[$name]}" ]; then
            same_count=$((same_count + 1))
        fi
    done
    echo "同名待校验: $same_count 张"

    if [ "$same_count" -gt 0 ]; then
        echo "批量计算基准 dHash ..."
        "$PY" "$DHASH_BATCH" scan "$LATEST_FULL" "$TMP_BASE_TSV"

        echo "批量计算 Sprite dHash ..."
        "$PY" "$DHASH_BATCH" scan "$INCOMING" "$TMP_CAND_TSV"

        echo "批量计算同名文件距离 ..."
        "$PY" "$DHASH_BATCH" same "$TMP_BASE_TSV" "$TMP_CAND_TSV" "$TMP_SAME_TSV"
        while IFS=$'\t' read -r name d fp; do
            [ -z "$d" ] && continue
            SAME_DIST["$name"]="$d"
        done < "$TMP_SAME_TSV"
    fi
fi

# ============ 7. 处理新增 / 重复 / 变更 ============
echo ""
echo "--- 处理新增 / 重复 / 变更 ---"

for f in "$INCOMING"/*; do
    [ -e "$f" ] || continue
    name="${f##*/}"
    [ "$name" = ".gitkeep" ] && continue
    if [[ "$name" == *"#"*".png" ]]; then
        echo "[忽略副本] $name"
        continue
    fi

    # ---- 同名：内容比对 ----
    if [ -n "${BASELINE_NAMES[$name]}" ]; then
        if [ "$USE_DHASH" = "1" ] && [ -n "${SAME_DIST[$name]:-}" ]; then
            d="${SAME_DIST[$name]}"
            if [ "$d" -le "$SAME_THRESHOLD" ]; then
                echo "[重复-同名同图] $name (hamming=$d)"
            else
                target=$(classify "$name")
                base_rel="${BASELINE_RELPATH[$name]}"

                # 新图 -> 根目录分类文件夹
                cp "$f" "$NEWVER/$target/$name"

                # 旧图 -> diff/changed/<分类>/
                mkdir -p "$NEWVER/diff/changed/$target"
                cp "$LATEST_FULL/$base_rel" "$NEWVER/diff/changed/$target/$name"

                echo "[变更-同名不同图] $name (hamming=$d) → 新图入 $target/，旧图入 diff/changed/$target/"
            fi
        else
            echo "[重复-同名] $name (dHash 未启用/失败，按文件名判定)"
        fi
        continue
    fi

    # ---- 首次出现：直接新增，不比对 ----
    target=$(classify "$name")
    cp "$f" "$NEWVER/$target/$name"
    BASELINE_NAMES["$name"]=1
    BASELINE_RELPATH["$name"]="$target/$name"
    echo "[新增-首次出现] $name → $target/"
done

# ============ 8. 处理删除（只输出本次删除） ============
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
        mkdir -p "$NEWVER/diff/deleted/$base_sub"
        cp "$LATEST_FULL/$base_rel" "$NEWVER/diff/deleted/$base_sub/$name"
        echo "[删除] $name (原属 $base_sub)"
    done
    echo "删除文件已放入 $NEWVER/diff/deleted/"
else
    echo "无删除文件，不创建 diff/deleted/ 目录"
fi

# ============ 9. 补 .gitkeep ============
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

if [ -d "$NEWVER/diff" ]; then
    for kind in changed deleted; do
        for sub in item_icon status_icon others; do
            d="$NEWVER/diff/$kind/$sub"
            [ -d "$d" ] || continue
            has_real=0
            for f in "$d"/*; do
                [ -e "$f" ] || continue
                fname="${f##*/}"
                if [ "$fname" != ".gitkeep" ]; then
                    has_real=1
                    break
                fi
            done
            if [ "$has_real" -eq 0 ]; then
                touch "$d/.gitkeep"
            fi
        done
    done
fi

rm -f "$TMP_BASE_TSV" "$TMP_CAND_TSV" "$TMP_SAME_TSV"

echo ""
echo "完成: 新增文件已分类到 $NEWVER/"