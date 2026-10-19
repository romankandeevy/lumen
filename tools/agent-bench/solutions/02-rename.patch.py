import pathlib, sys
root = pathlib.Path(sys.argv[1])
(root / "shop/pricing.py").write_text('''import warnings


def order_total(items, discount=0):
    """Сумма заказа в копейках: items — [(цена, количество)], discount — процент скидки."""
    total = sum(price * qty for price, qty in items)
    return total - total * discount // 100


def calc_total(items, discount=0):
    """Устаревшее имя order_total."""
    warnings.warn("calc_total устарела, используй order_total", DeprecationWarning, stacklevel=2)
    return order_total(items, discount)
''')
(root / "shop/__init__.py").write_text("from .pricing import order_total, calc_total\n")
for name in ["shop/cart.py", "shop/receipt.py", "shop/report.py", "test_shop.py"]:
    p = root / name
    p.write_text(p.read_text().replace("calc_total", "order_total"))
(root / "README.md").write_text("# shop\n\n`order_total(items, discount=0)` — сумма заказа в копейках. Старое имя `calc_total` устарело.\n")
