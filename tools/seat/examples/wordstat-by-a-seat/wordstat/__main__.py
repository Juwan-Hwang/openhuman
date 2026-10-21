import argparse
import json
import sys

from . import top_words


def main(argv=None):
    p = argparse.ArgumentParser(prog="wordstat")
    p.add_argument("file", nargs="?", help="input file (default stdin)")
    p.add_argument("-n", type=int, default=10)
    p.add_argument("--stopwords", help="file with one stopword per line")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    text = open(a.file, encoding="utf-8").read() if a.file else sys.stdin.read()
    stop = []
    if a.stopwords:
        stop = open(a.stopwords, encoding="utf-8").read().split()
    rows = top_words(text, a.n, stopwords=stop)
    if a.json:
        print(json.dumps([{"word": w, "count": c} for w, c in rows], ensure_ascii=False))
    else:
        for w, c in rows:
            print(f"{c}\t{w}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
