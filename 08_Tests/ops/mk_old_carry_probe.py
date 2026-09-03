#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""중복 제거 이전(구판) 러너 **사본**을 만든다 (양성 대조용).

공유 러너를 잠깐이라도 되돌리면 그 창에 스케줄러 tick 이 끼어들어 무인 루프가
구판으로 돈다. 그래서 사본에만 주입한다(mk_old_pending_probe.py 와 같은 사유).

출력: 사본 경로 1줄. 주입 지점을 못 찾으면 아무것도 출력하지 않고 exit 1.
"""
import io
import os
import sys
import tempfile

# ★2026-09-04: 헬퍼가 rf_spec_sig.R 정본으로 올겨갔다(09-03). 대상을 함께 옮긴다.
#   spec 경로 축(spec_%s__%s.json)은 여전히 러너에 있고 검사 ⑥가 살아있는 정본을 직접 본다 —
#   이 프로브는 **중복제거 축** 하나만 되돌린다(합성 주입은 어느 축이 발화했는지 못 가른다).
SRC = "02_Infrastructure/reinforcement/rf_spec_sig.R"
DEDUP_NEW = ('.dedup_factors <- function(fs) { seen <- character(0); out <- list()\n'
             '  for (f in fs %||% list()) { k <- .fkey(f)\n'
             '    if (!(k %in% seen)) { seen <- c(seen, k); out[[length(out) + 1L]] <- f } }\n'
             '  out }')
DEDUP_OLD = '.dedup_factors <- function(fs) fs %||% list()'
SPEC_NEW = 'sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48))'
SPEC_OLD = 'sprintf("spec_%s.json", CELL$code)'


def main():
    path = os.path.join(os.environ.get("QM_ROOT", "."), SRC)
    try:
        s = io.open(path, encoding="utf-8").read()
    except OSError:
        return 1
    if DEDUP_NEW not in s:
        return 1                       # 구현이 바뀌었다 — 검사기가 낡았음을 알린다
    out = os.path.join(tempfile.gettempdir(), "rf_carry_old.R")
    with io.open(out, "w", encoding="utf-8", newline="") as f:
        f.write(s.replace(DEDUP_NEW, DEDUP_OLD))
    sys.stdout.write(out.replace("\\", "/") + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
