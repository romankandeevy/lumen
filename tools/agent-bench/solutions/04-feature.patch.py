import pathlib, sys
root = pathlib.Path(sys.argv[1])
p = root / "todo.py"
s = p.read_text()
s = s.replace('''    elif cmd == "list":
        for it in items:
            print(f"{it['id']}. {it['text']}")''', '''    elif cmd == "done":
        found = [it for it in items if args and str(it["id"]) == args[0]]
        if not found:
            print(f"Нет дела с номером {args[0] if args else '?'}", file=sys.stderr)
            return 1
        found[0]["done"] = True
        save(items)
        print(f"Сделано: {found[0]['id']}")
    elif cmd == "list":
        if "--json" in args:
            print(json.dumps(items, ensure_ascii=False))
            return 0
        for it in items:
            print(f"{it['id']}. [{'x' if it['done'] else ' '}] {it['text']}")''')
s = s.replace('print("Команды: add, list")', 'print("Команды: add, done, list [--json]")')
p.write_text(s)
(root / "README.md").write_text("# todo\n\n`add <текст>`, `done <id>`, `list`, `list --json`.\n")
t = root / "test_todo.py"
t.write_text(t.read_text().replace('"1. купить хлеб"', '"1. [ ] купить хлеб"').replace("    def test_add_and_list(self):", '''    def test_done(self):
        with tempfile.TemporaryDirectory() as d:
            run("add", "a", cwd=d)
            run("done", "1", cwd=d)
            self.assertIn("[x] a", run("list", cwd=d).stdout)

    def test_add_and_list(self):'''))
