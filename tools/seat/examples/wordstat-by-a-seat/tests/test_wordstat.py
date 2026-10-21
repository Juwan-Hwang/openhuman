from wordstat import count_words, top_words
from wordstat.__main__ import main


def test_count():
    assert count_words("a b A")["a"] == 2


def test_top():
    assert top_words("x y y z z z", 2) == [("z", 3), ("y", 2)]


def test_cli(tmp_path, capsys):
    f = tmp_path / "t.txt"
    f.write_text("hi hi you")
    assert main([str(f), "-n", "1"]) == 0
    assert capsys.readouterr().out == "2\thi\n"


def test_stopwords_json(tmp_path, capsys):
    f = tmp_path / "t.txt"
    f.write_text("the cat the dog the cat")
    s = tmp_path / "stop.txt"
    s.write_text("the\n")
    assert main([str(f), "--stopwords", str(s), "--json", "-n", "1"]) == 0
    assert capsys.readouterr().out.strip() == '[{"word": "cat", "count": 2}]'

