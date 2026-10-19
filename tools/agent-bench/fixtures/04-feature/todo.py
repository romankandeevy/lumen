"""Список дел в файле todo.json: `python3 todo.py add "купить хлеб"`, `python3 todo.py list`."""
import json
import pathlib
import sys

FILE = pathlib.Path("todo.json")


def load():
    return json.loads(FILE.read_text()) if FILE.exists() else []


def save(items):
    FILE.write_text(json.dumps(items, ensure_ascii=False, indent=2))


def main(argv):
    if not argv:
        print("Команды: add, list")
        return 1
    items = load()
    cmd, args = argv[0], argv[1:]
    if cmd == "add":
        items.append({"id": len(items) + 1, "text": " ".join(args), "done": False})
        save(items)
        print(f"Добавлено: {items[-1]['id']}")
    elif cmd == "list":
        for it in items:
            print(f"{it['id']}. {it['text']}")
    else:
        print(f"Нет команды: {cmd}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
