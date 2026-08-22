# -*- coding: utf-8 -*-
"""canonical_screen(alpha 단계) ↔ forge(권위) PORT_t 괴리 측정.

★왜: 오늘 실측에서 alpha 단계의 canonical_screen PORT_t **0.926** 이 최종 forge **0.837** 을
  예고했다(calmar 0.231→0.212, mdd 0.670→0.669). 그렇다면 41분 시점에 탈락을 알 수 있고
  적체 산술이 81일 → 23일로 바뀐다.
  **그러나 n=1 이다.** 그리고 헌법이 반대 전례를 기록하고 있다 —
  "E2E: FLOW proxy portfolio-α t 3.55 → forge 실측 2.35"(§1) = **proxy 가 과대 표시한** 사례.
  과대 방향이면 조기탈락이 **살릴 것을 버린다**.

⇒ 조기탈락 기준을 정하기 전에 **괴리 분포**를 먼저 잰다. 기준 설정은 그 다음이고,
  §3(사전등록) 상 성과를 보고 문턱을 고르면 사후 자유도다.

측정: alpha_package(canonical_screen) 와 forge_package/bt_result(backtested)가 **둘 다 있는**
WT 를 찾아 짝지어 비교한다. 짝이 없으면 그것 자체가 결론이다(측정 불가 ≠ 괴리 없음).
"""
import glob
import io
import json
import os
import re

ROOT = 'qepm/mailbox/worktask'


def deep_get(o, pats):
    """중첩 JSON 에서 키 이름이 패턴에 맞는 첫 수치를 찾는다."""
    found = []

    def walk(x, path=''):
        if isinstance(x, dict):
            for k, v in x.items():
                kp = path + '/' + str(k)
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    for p in pats:
                        if re.search(p, str(k), re.I):
                            found.append((kp, float(v)))
                walk(v, kp)
        elif isinstance(x, list):
            for i, v in enumerate(x):
                walk(v, path + '[%d]' % i)
    walk(o)
    return found


rows = []
for d in sorted(glob.glob(os.path.join(ROOT, 'WT-*'))):
    ap = os.path.join(d, 'alpha_package.json')
    fp = os.path.join(d, 'forge_package.json')
    if not (os.path.exists(ap) and os.path.exists(fp)):
        continue
    try:
        a = json.load(io.open(ap, encoding='utf-8'))
        f = json.load(io.open(fp, encoding='utf-8'))
    except Exception:
        continue
    sa = deep_get(a, [r'^port_t$', r'portfolio_alpha_t', r'port_t_nw'])
    sf = deep_get(f, [r'^port_t$', r'portfolio_alpha_t', r'port_t_nw'])
    if not sa or not sf:
        continue
    rows.append({'wt': os.path.basename(d),
                 'screen': sa[0][1], 'screen_key': sa[0][0],
                 'forge': sf[0][1], 'forge_key': sf[0][0]})

print("alpha_package ∧ forge_package 동시 보유 WT: %d건" % len(rows))
print()
if not rows:
    print("★짝이 0건 — 괴리를 측정할 수 없다.")
    print("  이것은 '괴리가 없다' 가 아니라 **'측정 불가'** 다(오늘 반복 확인한 구분).")
    print("  ⇒ 조기탈락 기준은 지금 정할 수 없다. 짝이 쌓일 때까지 전 단계 처리가 필요하다.")
    raise SystemExit

print("%-24s %10s %10s %9s" % ("WT", "screen", "forge", "차이"))
print("-" * 58)
diffs = []
for r in sorted(rows, key=lambda x: x['wt']):
    d = r['forge'] - r['screen']
    diffs.append(d)
    print("%-24s %10.4f %10.4f %+9.4f" % (r['wt'], r['screen'], r['forge'], d))

n = len(diffs)
diffs.sort()
mean = sum(diffs) / n
print()
print("괴리(forge − screen): n=%d · 평균 %+.4f · 중앙 %+.4f · 최소 %+.4f · 최대 %+.4f"
      % (n, mean, diffs[n // 2], diffs[0], diffs[-1]))
over = sum(1 for d in diffs if d < 0)   # forge < screen = screen 이 과대
print("  screen 이 **과대** 표시한 건: %d/%d (%.0f%%)  ← 이 방향이면 조기탈락이 안전"
      % (over, n, 100.0 * over / n))
print("  screen 이 **과소** 표시한 건: %d/%d (%.0f%%)  ← 이 방향이면 살릴 것을 버린다"
      % (n - over, n, 100.0 * (n - over) / n))
print()
print("★조기탈락 문턱을 정하려면 **과소 방향의 최대 크기**가 필요하다 —")
print("  screen 이 x 만큼 과소할 수 있으면 문턱은 (2.95 − x) 아래로 못 내린다.")
worst_under = max([d for d in diffs if d > 0], default=0.0)
print("  현 표본 최대 과소: %+.4f ⇒ 안전 문턱 상한 ≈ %.3f" % (worst_under, 2.95 - worst_under))
