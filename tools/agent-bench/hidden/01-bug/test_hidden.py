import unittest
from dates import parse


class Hidden(unittest.TestCase):
    def test_dots(self):
        self.assertEqual(parse("19.10.2026"), (2026, 10, 19))
        self.assertEqual(parse(" 01.02.2026 "), (2026, 2, 1))

    def test_words(self):
        self.assertEqual(parse("19 окт 2026"), (2026, 10, 19))
        self.assertEqual(parse("1 мая 2026"), (2026, 5, 1))

    def test_leap_years(self):
        # 1900 и 2100 — не високосные, 2000 — високосный
        with self.assertRaises(ValueError):
            parse("29.02.1900")
        with self.assertRaises(ValueError):
            parse("2100-02-29")
        self.assertEqual(parse("29.02.2000"), (2000, 2, 29))
        self.assertEqual(parse("29.02.2028"), (2028, 2, 29))

    def test_bad(self):
        for bad in ["31.04.2026", "2026-13-01", "0.10.2026"]:
            with self.assertRaises(ValueError):
                parse(bad)


if __name__ == "__main__":
    unittest.main()
