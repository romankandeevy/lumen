import pathlib, sys
root = pathlib.Path(sys.argv[1])
(root / "mdtable.py").write_text(r'''import sys
import unicodedata


def width(s):
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in s)


def cells(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|") and not line.endswith("\\|"):
        line = line[:-1]
    out, cur, i = [], "", 0
    while i < len(line):
        if line[i] == "\\" and i + 1 < len(line) and line[i + 1] == "|":
            cur += "\\|"; i += 2; continue
        if line[i] == "|":
            out.append(cur.strip()); cur = ""
        else:
            cur += line[i]
        i += 1
    out.append(cur.strip())
    return out


def format_table(text):
    lines = [l for l in text.strip("\n").split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if len(lines) < 2 or not set(lines[1].replace("|", "").replace(" ", "")) <= set("-:") or "-" not in lines[1]:
        raise ValueError("это не таблица Markdown: второй строкой должен быть разделитель вида |---|---|")
    rows = [cells(l) for l in lines]
    seps = rows.pop(1)
    n = max(len(r) for r in rows + [seps])
    rows = [r + [""] * (n - len(r)) for r in rows]
    seps = seps + ["---"] * (n - len(seps))
    align = ["center" if s.startswith(":") and s.endswith(":") else "right" if s.endswith(":") else "left" for s in seps]
    w = [max(3, max(width(r[j]) for r in rows)) for j in range(n)]

    def pad(s, j):
        gap = w[j] - width(s)
        if align[j] == "right":
            return " " * gap + s
        if align[j] == "center":
            return " " * (gap // 2) + s + " " * (gap - gap // 2)
        return s + " " * gap

    def sep(j):
        a = align[j]
        if a == "center":
            return ":" + "-" * (w[j] - 2) + ":"
        if a == "right":
            return "-" * (w[j] - 1) + ":"
        return (":" + "-" * (w[j] - 1)) if seps[j].startswith(":") else "-" * w[j]

    out = ["| " + " | ".join(pad(c, j) for j, c in enumerate(rows[0])) + " |",
           "| " + " | ".join(sep(j) for j in range(n)) + " |"]
    out += ["| " + " | ".join(pad(c, j) for j, c in enumerate(r)) + " |" for r in rows[1:]]
    return "\n".join(out)


if __name__ == "__main__":
    try:
        print(format_table(sys.stdin.read()))
    except ValueError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
''')
(root / "test_mdtable.py").write_text('''import unittest
from mdtable import format_table


class T(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(format_table("|a|\\n|-|\\n|b|"), "| a   |\\n| --- |\\n| b   |")


if __name__ == "__main__":
    unittest.main()
''')
