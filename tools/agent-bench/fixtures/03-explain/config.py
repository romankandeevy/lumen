"""Настройки сервера: по умолчанию → файл settings.ini → переменные окружения (главнее всего)."""
import configparser
import os

DEFAULTS = {"host": "127.0.0.1", "port": "8000", "debug": "false"}
ENV = {"host": "APP_HOST", "port": "APP_PRT", "debug": "APP_DEBUG"}


def load(path="settings.ini"):
    cfg = dict(DEFAULTS)
    parser = configparser.ConfigParser()
    if parser.read(path):
        cfg.update(parser["server"])
    for key, var in ENV.items():
        if var in os.environ:
            cfg[key] = os.environ[var]
    cfg["port"] = int(cfg["port"])
    cfg["debug"] = cfg["debug"].lower() in ("1", "true", "yes")
    return cfg
