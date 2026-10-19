#!/bin/bash
# Скрытые проверки по всем копиям задач: tools/agent-bench/check.sh ~/bench
# Проверки запускаются во временной копии — в папках агентов ничего не меняется.
set -uo pipefail
OUT="${1:?папка с задачами, например ~/bench}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TSV=$(mktemp)
for task in "$HERE"/fixtures/*/; do
    name=$(basename "$task")
    for tool in "$OUT"/*/; do
        dir="${tool%/}/$name"
        t=$(basename "$tool")
        if [ ! -d "$dir" ]; then printf "%s\t%s\t—\n" "$name" "$t" >>"$TSV"; continue; fi
        log="$dir.check.log"
        if [ -f "$HERE/hidden/$name/check.py" ]; then
            # задача без правок: смотрим прямо в папке агента, что он ничего не тронул
            (cd "$dir" && python3 -I "$HERE/hidden/$name/check.py" >"$log" 2>&1) && r="ок" || r="ПРОВАЛ"
        else
            tmp=$(mktemp -d)
            cp -R "$dir/." "$tmp/"
            cp -R "$HERE/hidden/$name/." "$tmp/"
            (cd "$tmp" && python3 -I -m unittest discover -q -p 'test_*.py' >"$log" 2>&1) && r="ок" || r="ПРОВАЛ"
            rm -rf "$tmp"
        fi
        [ "$r" = "ок" ] && [ ! -f "$HERE/hidden/$name/check.py" ] && rm -f "$log"
        printf "%s\t%s\t%s\n" "$name" "$t" "$r" >>"$TSV"
    done
done
python3 -I - "$TSV" <<'PY'
import sys, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
tools = list(dict.fromkeys(r[1] for r in rows))
tasks = list(dict.fromkeys(r[0] for r in rows))
res = {(r[0], r[1]): r[2] for r in rows}
print("задача".ljust(12) + "".join(t.ljust(14) for t in tools))
for task in tasks:
    print(task.ljust(12) + "".join(res.get((task, t), "—").ljust(14) for t in tools))
score = collections.Counter(t for (task, t), r in res.items() if r == "ок")
print("итого".ljust(12) + "".join(f"{score[t]} из {len(tasks)}".ljust(14) for t in tools))
PY
rm -f "$TSV"
echo "Провалы — в <папка задачи>.check.log. Задача 3: сверь ответ агента с ключом (он в 03-explain.check.log)."
