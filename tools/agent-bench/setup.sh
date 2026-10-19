#!/bin/bash
# Пять одинаковых задач для сравнения Claude Code, Codex и Lumen (docs/agent-bench.md).
#
#   tools/agent-bench/setup.sh ~/bench        — по копии каждой задачи на каждый инструмент: ~/bench/<инструмент>/<задача>
#   tools/agent-bench/check.sh ~/bench        — скрытые проверки по всем копиям, таблица результатов
#
# Каждая копия — отдельный git-репозиторий с первым коммитом: видно, что агент поменял, и задача 3 проверяет «ничего не трогал».
set -euo pipefail
OUT="${1:?папка, куда разложить задачи, например ~/bench}"
HERE="$(cd "$(dirname "$0")" && pwd)"
for tool in claude-code codex lumen; do
    for task in "$HERE"/fixtures/*/; do
        name=$(basename "$task")
        dest="$OUT/$tool/$name"
        [ -e "$dest" ] && { echo "уже есть: $dest (удали, чтобы разложить заново)"; continue; }
        mkdir -p "$dest"
        cp -R "$task". "$dest"
        (cd "$dest" && git init -q && git add -A && git -c user.email=bench@lumen -c user.name=bench commit -qm "задача $name")
    done
done
echo "==> разложено в $OUT: $(ls "$OUT" | tr '\n' ' ')"
echo "Дальше: в каждой папке дай инструменту текст из TASK.md (одинаково везде), потом tools/agent-bench/check.sh $OUT"
