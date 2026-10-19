"""Разбор дат из писем клиентов: «19.10.2026», «2026-10-19», «19 окт 2026»."""

MONTHS = {"янв": 1, "фев": 2, "мар": 3, "апр": 4, "май": 5, "мая": 5, "июн": 6,
          "июл": 7, "авг": 8, "сен": 9, "окт": 10, "ноя": 11, "дек": 12}


def is_leap(year):
    return year % 4 == 0


def days_in_month(year, month):
    if month == 2:
        return 29 if is_leap(year) else 28
    return 30 if month in (4, 6, 9, 11) else 31


def parse(text):
    """Вернуть (год, месяц, день) или бросить ValueError."""
    text = text.strip().lower()
    if "-" in text:
        y, m, d = text.split("-")
    elif "." in text:
        m, d, y = text.split(".")
    else:
        d, mon, y = text.split()
        m = MONTHS[mon[:3]]
    y, m, d = int(y), int(m), int(d)
    if not 1 <= m <= 12 or not 1 <= d <= days_in_month(y, m):
        raise ValueError(f"нет такой даты: {text}")
    return (y, m, d)
