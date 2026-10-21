# wordstat, written from the human seat

Claude Code was the *caller* here: it thought it was talking to a model named
`openhuman-human`. Behind that model sat another AI in the OpenHuman human
seat, doing the work with `oh-seat` and nothing else. No human touched it.

Two turns, as Claude Code sent them:

1. 在 proj/ 里写一个 Python 小库 wordstat：统计文本词频，带 CLI 和 pytest 测试，跑通测试后告诉我结果
2. 给 wordstat 加停用词过滤（--stopwords 文件）和 --json 输出，补测试，然后用它统计 proj 下所有 .py 文件的词频前 5

What the seat typed (relative paths resolve against Claude Code's cwd):

```sh
oh-seat next                                   # the request, the 12 tools, caller env
oh-seat tool Bash command="mkdir -p proj/wordstat proj/tests"
oh-seat tool Write file_path=proj/wordstat/__init__.py content=@- \
           + Write file_path=proj/wordstat/__main__.py content=@- \
           + Write file_path=proj/tests/test_wordstat.py content=@- <<'EOF'
...three files, separated by lines holding only @@@...
EOF
oh-seat tool Bash command="cd proj && python3 -m pytest -q"
oh-seat reply "做好了：…3 个 pytest 测试全部通过。"

# turn 2
oh-seat tool Edit file_path=proj/wordstat/__init__.py old_string=@- new_string=@- \
           + Edit file_path=proj/wordstat/__main__.py old_string=@- new_string=@- <<'EOF'
...
EOF
oh-seat tool Bash command="cd proj && python3 -m pytest -q"
#   TOOL RESULT Bash status=failed exit_code=1
#   NameError: name 'json' is not defined     <- the seat forgot an import
oh-seat tool Edit file_path=proj/wordstat/__main__.py old_string="import argparse" new_string=$'import argparse\nimport json'
oh-seat tool Bash command="cd proj && python3 -m pytest -q && cat wordstat/*.py tests/*.py | python3 -m wordstat -n 5 --json"
oh-seat reply "加好了…4 个全过（中途漏了 import json，已修）。"
```

The forgotten import is left in the story on purpose: the failed run is what
taught `oh-seat` to print `status=failed` instead of a "success" with a
footnote, and the retyped absolute paths are what made relative paths work.
