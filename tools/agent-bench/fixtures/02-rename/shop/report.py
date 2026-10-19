from shop.pricing import calc_total as total_of


def daily(orders):
    """Выручка за день: orders — список заказов, у каждого items и discount."""
    return sum(total_of(o["items"], o.get("discount", 0)) for o in orders)
