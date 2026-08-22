# -*- coding: utf-8 -*-
"""러너 스크립트에서 완주 알림 블록만 떼어낸다 (test_run_completion_notify.sh 전용).

검사 본문에 heredoc 을 중첩하면 이스케이프가 접혀 조용히 다른 코드를 검사하게 된다
(2026-08-22 실사고 계통). 추출을 파일로 분리해 그 위험을 없앤다.
"""
import io
import sys

src = io.open(sys.argv[1], encoding="utf-8", newline="").read()
L = src.replace(chr(13) + chr(10), chr(10)).split(chr(10))
try:
    st = next(k for k, l in enumerate(L) if "완주할 때마다" in l)
    en = next(k for k in range(st, len(L))
              if L[k].strip() == "fi" and "$_RS" in L[k - 1])
except StopIteration:
    sys.exit(1)
sys.stdout.write(chr(10).join(L[st:en + 1]))
