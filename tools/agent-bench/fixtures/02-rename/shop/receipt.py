from . import pricing


def receipt(items, discount=0):
    lines = [f"{price / 100:.2f} × {qty}" for price, qty in items]
    lines.append(f"Итого: {pricing.calc_total(items, discount) / 100:.2f}")
    return "\n".join(lines)
