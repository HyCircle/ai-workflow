#!/usr/bin/env python3
"""假的 cursor-agent / claude / codex:按环境变量产出各自格式的输出,并记录收到的命令行与标准输入。

FAKE_MODE: ok(默认)| error | none(流截断)| sleep(派生子进程后挂起)
FAKE_TEXT: 最终回复;FAKE_TOUCH: 逗号分隔的相对路径,运行时追加一行内容(模拟施工)。
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

name = Path(sys.argv[0]).name
mode = os.environ.get("FAKE_MODE", "ok")
text = os.environ.get("FAKE_TEXT", "OK")
stdin = sys.stdin.read() if name != "cursor-agent" else ""
Path(os.environ["FAKE_RECORD"]).write_text(json.dumps({"argv": sys.argv, "stdin": stdin}))

for rel in filter(None, os.environ.get("FAKE_TOUCH", "").split(",")):
    with open(rel, "a") as f:
        f.write("worker 改动\n")

print("half-line not json")
if mode == "sleep":
    child = subprocess.Popen(["sleep", "60"])
    Path(os.environ["FAKE_CHILD_PIDFILE"]).write_text(str(child.pid))
    time.sleep(60)
elif mode == "none":
    sys.exit(1)
elif name == "codex":
    if mode == "error":
        print(json.dumps({"type": "turn.failed", "error": {"message": "boom"}}))
        sys.exit(1)
    Path(sys.argv[sys.argv.index("-o") + 1]).write_text(text + "\n")
    print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 2}}))
else:
    ok = mode == "ok"
    print(json.dumps({"type": "result", "subtype": "success" if ok else "error", "is_error": not ok,
                      "result": text if ok else "boom", "usage": {"inputTokens": 1}}))
