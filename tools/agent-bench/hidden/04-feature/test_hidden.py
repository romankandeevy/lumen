import json, pathlib, subprocess, sys, tempfile, unittest

TODO = str(pathlib.Path("todo.py").resolve())


def run(*args, cwd):
    return subprocess.run([sys.executable, TODO, *args], cwd=cwd, capture_output=True, text=True)


class Hidden(unittest.TestCase):
    def test_done_and_marks(self):
        with tempfile.TemporaryDirectory() as d:
            run("add", "раз", cwd=d); run("add", "два", cwd=d)
            r = run("done", "1", cwd=d)
            self.assertEqual(r.returncode, 0)
            out = run("list", cwd=d).stdout
            self.assertIn("1. [x] раз", out)
            self.assertIn("2. [ ] два", out)

    def test_done_unknown(self):
        with tempfile.TemporaryDirectory() as d:
            run("add", "раз", cwd=d)
            r = run("done", "7", cwd=d)
            self.assertEqual(r.returncode, 1)
            self.assertTrue((r.stdout + r.stderr).strip())

    def test_json(self):
        with tempfile.TemporaryDirectory() as d:
            run("add", "хлеб", cwd=d); run("done", "1", cwd=d)
            data = json.loads(run("list", "--json", cwd=d).stdout)
            self.assertEqual(data, [{"id": 1, "text": "хлеб", "done": True}])

    def test_readme_and_tests_updated(self):
        readme = pathlib.Path("README.md").read_text()
        self.assertIn("done", readme)
        self.assertIn("--json", readme)
        self.assertIn("done", pathlib.Path("test_todo.py").read_text())


if __name__ == "__main__":
    unittest.main()
