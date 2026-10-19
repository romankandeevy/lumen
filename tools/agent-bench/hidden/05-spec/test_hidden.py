import subprocess, sys, unittest, pathlib
from mdtable import format_table


class Hidden(unittest.TestCase):
    def test_basic_left(self):
        src = "|a|bb|\n|-|-|\n|ccc|d|"
        self.assertEqual(format_table(src), "| a   | bb  |\n| --- | --- |\n| ccc | d   |")

    def test_alignments(self):
        src = "| left | center | right |\n|:--|:-:|--:|\n| x | y | z |"
        self.assertEqual(format_table(src),
                         "| left | center | right |\n| :--- | :----: | ----: |\n| x    |   y    |     z |")

    def test_cyrillic_and_wide(self):
        src = "| имя | ✅ |\n|---|---|\n| Рома | 日本 |"
        out = format_table(src).split("\n")
        self.assertEqual(out[0], "| имя  | ✅   |")
        self.assertEqual(out[2], "| Рома | 日本 |")

    def test_escaped_pipe(self):
        src = "| a | b |\n|---|---|\n| x \\| y | z |"
        self.assertEqual(format_table(src).split("\n")[2], "| x \\| y | z   |")

    def test_ragged_rows(self):
        src = "| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |"
        out = format_table(src).split("\n")
        self.assertEqual(out[0], "| a   | b   |     |")
        self.assertEqual(out[1], "| --- | --- | --- |")
        self.assertEqual(out[2], "| 1   |     |     |")
        self.assertEqual(out[3], "| 1   | 2   | 3   |")

    def test_blank_lines_and_trailing(self):
        self.assertEqual(format_table("\n\n|a|\n|-|\n|b|\n\n"), "| a   |\n| --- |\n| b   |")

    def test_not_a_table(self):
        with self.assertRaises(ValueError):
            format_table("| a | b |\n| c | d |")

    def test_cli(self):
        ok = subprocess.run([sys.executable, "mdtable.py"], input="|a|\n|-|\n|b|", capture_output=True, text=True)
        self.assertEqual(ok.returncode, 0)
        self.assertEqual(ok.stdout.strip(), "| a   |\n| --- |\n| b   |")
        bad = subprocess.run([sys.executable, "mdtable.py"], input="просто текст", capture_output=True, text=True)
        self.assertEqual(bad.returncode, 1)
        self.assertTrue(bad.stderr.strip())

    def test_agent_wrote_tests(self):
        tests = list(pathlib.Path(".").glob("test_*.py"))
        tests = [t for t in tests if t.name != "test_hidden.py"]
        self.assertTrue(tests, "нет своих тестов")


if __name__ == "__main__":
    unittest.main()
