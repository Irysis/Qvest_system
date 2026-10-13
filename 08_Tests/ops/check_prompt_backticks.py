# -*- coding: utf-8 -*-
"""쉘 스크립트의 큰따옴표 프롬프트 안 **미이스케이프 백틱** 탐지.

★왜 별도 검사기인가: `bash -n` 은 이걸 못 잡는다. 명령 치환은 적법 구문이라
문법 검사를 통과하고, 실행 시점에야 `ABORT.txt: command not found` 로 터진다.
2026-08-30 실사고 — 프롬프트 한 줄의 백틱 한 쌍이 그 뒤 한글까지 삼켜
충실구현 에이전트가 세 번 연속 no_engine 으로 죽었다.

사용: python check_prompt_backticks.py <file...>   (rc=1 = 위반)
"""
import io, re, sys

def scan(path):
    src = io.open(path, "rb").read().decode("utf-8", "replace")
    hits, in_prompt = [], False
    for i, line in enumerate(src.split("\n"), 1):
        single = False
        if re.match(r'^[A-Z_]+="', line):            # PROMPT="... 시작
            in_prompt = True
            # ★한 줄 대입(RB_SH="..."; ... RB_SH="...")은 그 줄에서 닫힌다 — 미이스케이프 큰따옴표 수가 짝수면 프롬프트가 아니다.
            #   구판은 이런 줄에서 프롬프트 모드에 들어가 '다음에 " 로 끝나는 줄'까지 끌고 갔다 → 사이의 bash 주석 백틱을 위반으로 셌다
            #   (10-13 실측: v10.01 이 rf_replication_auto.sh 의 활성 entry 게이트를 지우자 닫는 줄이 사라져 104행 주석이 걸렸다).
            nq = len(re.findall(r'(?<!\\)"', line))
            single = (nq % 2 == 0)
        if not in_prompt:
            continue
        # 백슬래시로 escape 되지 않은 백틱만 센다
        for m in re.finditer(r'`', line):
            j, n = m.start() - 1, 0
            while j >= 0 and line[j] == "\\":
                n += 1; j -= 1
            if n % 2 == 0:
                hits.append((i, line.strip()[:70]))
        if single:                                    # 한 줄 대입 — 백틱은 위에서 쟀고 여기서 닫는다
            in_prompt = False
            continue
        if line.rstrip().endswith('"') and not line.rstrip().endswith('\\"') and in_prompt and i > 1:
            if re.match(r'^[A-Z_]+="', line) is None:
                in_prompt = False
    return hits

rc = 0
for p in sys.argv[1:]:
    for ln, txt in scan(p):
        print("  위반 %s:%d  %s" % (p, ln, txt)); rc = 1
sys.exit(rc)
