def calc_total(items, discount=0):
    """Сумма заказа в копейках: items — [(цена, количество)], discount — процент скидки."""
    total = sum(price * qty for price, qty in items)
    return total - total * discount // 100
