"""wordstat: count word frequencies."""
import re
from collections import Counter

__all__ = ["count_words", "top_words"]

_WORD = re.compile(r"[\w']+", re.UNICODE)


def count_words(text, lower=True, stopwords=()):
    words = _WORD.findall(text.lower() if lower else text)
    stop = {w.lower() if lower else w for w in stopwords}
    return Counter(w for w in words if w not in stop)


def top_words(text, n=10, lower=True, stopwords=()):
    return count_words(text, lower, stopwords).most_common(n)
