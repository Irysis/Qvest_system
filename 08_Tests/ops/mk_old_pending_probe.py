#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""구판 pending 술어를 주입한 러너 **사본**을 만든다 (양성 대조용).

왜 사본인가: 공유 러너를 잠깐이라도 되돌리면 그 창에 스케줄러 tick 이 끼어들어
살아있는 무인 루프가 구판으로 돈다(2026-08-30 설정 격리와 같은 사유).

왜 이 파일이 따로 있는가: 검사 스크립트 안 heredoc 에 파이썬을 넣으면 셸 인용과
백틱이 얽힌다 — 이 저장소에서 이미 두 번 물린 자리다(check_prompt_backticks.py 의 존재 이유).

출력: 사본 경로 1줄. 술어를 못 찾으면 아무것도 출력하지 않고 exit 1
      (검사기가 "주입 실패" 와 "검사 통과" 를 구분할 수 있게).
"""
import io
import os
import sys
import tempfile

SRC = "02_Infrastructure/ops/reinforce_auto_parallel.R"
NEW = ("pending <- Filter(function(a) (is.null(a$essence) || is.null(a$essence$port_t)) "
       "&& !isTRUE(a$terminal),\n                  E$attempts)")
OLD = "pending <- Filter(function(a) is.null(a$essence) || is.null(a$essence$port_t), E$attempts)"


def main():
    root = os.environ.get("QM_ROOT", ".")
    path = os.path.join(root, SRC)
    try:
        s = io.open(path, encoding="utf-8").read()
    except OSError:
        return 1
    if NEW not in s:
        return 1                       # 술어가 바뀌었다 — 검사기가 낡았음을 호출자에게 알린다
    out = os.path.join(tempfile.gettempdir(), "rf_pred_old.R")
    with io.open(out, "w", encoding="utf-8", newline="") as f:
        f.write(s.replace(NEW, OLD))
    sys.stdout.write(out.replace("\\", "/") + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
