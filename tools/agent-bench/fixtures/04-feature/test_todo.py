import os, subprocess, sys, tempfile, unittest, pathlib

TODO = str(pathlib.Path(__file__).with_name("todo.py").resolve())


def run(*args, cwd):
    return subprocess.run([sys.executable, TODO, *args], cwd=cwd, capture_output=True, text=True)


class TestTodo(unittest.TestCase):
    def test_add_and_list(self):
        with tempfile.TemporaryDirectory() as d:
            run("add", "купить", "хлеб", cwd=d)
            out = run("list", cwd=d).stdout
            self.assertIn("1. купить хлеб", out)


if __name__ == "__main__":
    unittest.main()
