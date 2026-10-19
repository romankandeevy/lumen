import unittest
from dates import parse


class TestParse(unittest.TestCase):
    def test_iso(self):
        self.assertEqual(parse("2026-10-19"), (2026, 10, 19))

    def test_dots(self):
        self.assertEqual(parse("19.10.2026"), (2026, 10, 19))


if __name__ == "__main__":
    unittest.main()
