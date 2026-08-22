# -*- coding: utf-8 -*-
"""큐 파일에서 상위 N개 대상 id 를 뽑는다 — 디스패치 **귀속** 기록용.

왜 있나 (실사고 2026-08-22 18:13):
  mode_queue 런이 WT-D20260822_005 를 SPEC_APPROVED → ALPHA_DONE 으로 올리고
  alpha_package.json(15KB) · certificate · validation 까지 냈다. 성공이다.
  그런데 **로그에 WT id 가 한 줄도 없었다**. 그래서 사후에 "이 런이 무엇을 했나" 를
  물었을 때, 같은 시각 병렬 세션이 만지던 다른 WT(007)의 산출을 이 런의 것으로
  오귀속했다 — 텔레그램으로 틀린 사실이 나갔다.

★기전: 원장 지문(research_effect_signature)은 **전역**이다. 저장소에 동시 세션이
  있으면 남의 진척도 CHANGED 로 읽힌다. 08-16 연속성 마커 사고와 같은 계통 —
  "남의 mtime 이 내 턴의 계약을 충족" 시켰던 그 구조다.
  전역 지문은 "무언가 바뀌었다" 는 답할 수 있어도 "내가 바꿨다" 는 답할 수 없다.

⇒ 최소 수리 = 디스패치 **전에** 무엇을 겨눴는지 남긴다. 귀속은 사후에 복원되지 않는다.
  (정본은 여전히 에이전트의 MODEQ_DONE 이다. 이건 그게 없을 때의 복원 실마리다.)
"""
import io
import json
import sys


def main(argv):
    if not argv:
        print("?")
        return 0
    n = int(argv[1]) if len(argv) > 1 else 3
    try:
        with io.open(argv[0], encoding="utf-8") as fh:
            d = json.load(fh)
    except Exception:
        print("?")
        return 0
    items = d if isinstance(d, list) else (d.get("items") or d.get("pending") or [])
    out = []
    for x in items[:n]:
        if not isinstance(x, dict):
            out.append(str(x))
            continue
        out.append(str(x.get("wt_id") or x.get("id") or x.get("strategy_id") or "?"))
    print(",".join(out) if out else "?")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
