#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""서명에서 유니버스 축을 뺀 러너 **사본**을 만든다 (중복 가드 양성 대조용).

축 일부만 보는 서명은 서로 다른 칸을 같다고 접는다 — 검사의 음성 대조가 무너져야 한다.
셸 sed 로 하려다 패턴의 '|' 가 구분자와 충돌해 조용히 실패했고, 빈 프로브에서 검사가
실패하는 것을 "발화" 로 오독했다(2026-08-31). 죽은 양성 대조가 그렇게 생긴다.

출력: 사본 경로 1줄. 대상 줄을 못 찾으면 아무것도 출력하지 않고 exit 1
      (검사기가 "주입 실패" 와 "검사 통과" 를 구분할 수 있게).
"""
import io
import os
import sys
import tempfile

SRC = "02_Infrastructure/ops/reinforce_auto_parallel.R"
NEEDLE = "as.character(toJSON(sp$universe"


def main():
    path = os.path.join(os.environ.get("QM_ROOT", "."), SRC)
    try:
        lines = io.open(path, encoding="utf-8").read().split("\n")
    except OSError:
        return 1
    hits = [i for i, l in enumerate(lines) if NEEDLE in l]
    if len(hits) != 1:
        return 1                       # 서명이 바뀌었다 — 검사기가 낡았음을 알린다
    del lines[hits[0]]
    out = os.path.join(tempfile.gettempdir(), "rf_sig_partial.R")
    with io.open(out, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines))
    sys.stdout.write(out.replace("\\", "/") + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
