import unittest
from shop import calc_total
from shop.cart import Cart
from shop.receipt import receipt
from shop.report import daily


class TestShop(unittest.TestCase):
    def test_total(self):
        self.assertEqual(calc_total([(1000, 2), (500, 1)]), 2500)
        self.assertEqual(calc_total([(1000, 1)], discount=10), 900)

    def test_cart(self):
        c = Cart()
        c.add(300, 3)
        self.assertEqual(c.total(), 900)

    def test_receipt(self):
        self.assertIn("Итого: 15.00", receipt([(1000, 1), (500, 1)]))

    def test_daily(self):
        self.assertEqual(daily([{"items": [(100, 1)]}, {"items": [(1000, 1)], "discount": 50}]), 600)


if __name__ == "__main__":
    unittest.main()
