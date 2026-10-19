from config import load


def main():
    cfg = load()
    print(f"Слушаю {cfg['host']}:{cfg['port']} (debug={cfg['debug']})")


if __name__ == "__main__":
    main()
