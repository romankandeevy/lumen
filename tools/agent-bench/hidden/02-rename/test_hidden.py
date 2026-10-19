import pathlib, re, unittest, warnings


class Hidden(unittest.TestCase):
    def test_new_name_everywhere(self):
        from shop import order_total
        from shop.cart import Cart
        from shop.report import daily
        self.assertEqual(order_total([(1000, 1)], discount=10), 900)
        c = Cart(); c.add(300, 3)
        self.assertEqual(c.total(), 900)
        self.assertEqual(daily([{"items": [(100, 1)]}]), 100)

    def test_old_name_still_works_with_warning(self):
        from shop import calc_total
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            self.assertEqual(calc_total([(100, 2)]), 200)
        self.assertTrue(any(issubclass(x.category, DeprecationWarning) for x in w))

    def test_old_name_only_in_alias(self):
        uses = []
        for p in pathlib.Path(".").rglob("*.py"):
            # тесты могут проверять и старое имя (что оно работает и предупреждает) — это правильно
            if p.name.startswith("test_"):
                continue
            for i, line in enumerate(p.read_text().splitlines(), 1):
                if "calc_total" in line:
                    uses.append(f"{p}:{i}")
        # старое имя — только в псевдониме (определение, предупреждение, экспорт)
        self.assertLessEqual(len(uses), 4, uses)
        self.assertIn("order_total", pathlib.Path("README.md").read_text())

if __name__ == "__main__":
    unittest.main()
