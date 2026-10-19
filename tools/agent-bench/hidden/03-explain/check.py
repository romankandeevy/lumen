"""Задача 3 — только объяснение. Проверяем: файлы не тронуты. Ответ агента сверяется руками по ключу ниже."""
import subprocess, sys
changed = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
print("файлы не тронуты" if not changed else "ТРОНУТЫ ФАЙЛЫ:\n" + changed)
print("Ключ: в config.py, строка 6, опечатка в имени переменной окружения: APP_PRT вместо APP_PORT. "
      "Исправление — \"port\": \"APP_PORT\". Хороший ответ ещё замечает, что README обещает APP_PORT.")
sys.exit(1 if changed else 0)
