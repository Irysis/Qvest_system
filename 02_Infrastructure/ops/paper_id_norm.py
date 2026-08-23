# -*- coding: utf-8 -*-
"""논문 id 정규화 **정본** (2026-08-22 신설).

왜 있나:
  같은 대상을 세는데 답이 셋이었다 — 좌초 논문 수가 **154 / 62 / 61**, 재발견이 **27회 / 10회**.
  세 수치 전부 개수는 정확했고 **정규화 규약이 달랐다**:
    · 제목 기준 vs id 기준
    · `arxiv:` 접두 · `v2` 버전접미 제거 여부
    · 창을 자르는가(처리일 이후만) 아닌가
  ⇒ 규약이 없으면 **어느 수치도 인용할 수 없다**. 여기서 한 번 정하고 소비자는 이걸 부른다.

★규약 (이 파일이 정본):
  1. **id 기준**으로 센다. 제목은 표기 변형·부제 절단이 잦아 같은 논문을 둘로 센다.
  2. `arxiv:` / `arXiv:` / `arxiv.org/abs/` 접두를 벗긴다.
  3. `v1`/`v2`… **버전 접미를 벗긴다** — 같은 논문의 개정판은 같은 논문이다.
  4. 공백·대소문자를 정규화한다. curated PDF id 는 파일명 그대로(확장자만 제거).
  5. **창(window)은 호출자가 명시**한다. 이 모듈은 id 만 정규화하고 기간은 정하지 않는다
     — 기간을 여기 숨기면 같은 함수가 호출처마다 다른 답을 낸다.

★이 규약은 `alpha_search_queue_prompt.md` §6 의 'bare arXiv id' 지시와 동일하다
  (그쪽이 먼저 명문화했고, 여기서 코드로 고정한다).
"""
import io
import json
import os
import re
import sys

_PREFIX = re.compile(r'^(?:arxiv\s*:|arxiv\.org/abs/|https?://arxiv\.org/abs/)', re.I)
_VERSUF = re.compile(r'v\d+$', re.I)


def norm_id(x):
    """논문 id 를 정본 형태로. 판별 불가면 빈 문자열(있는 척하지 않는다)."""
    if x is None:
        return ''
    s = str(x).strip()
    if not s:
        return ''
    s = _PREFIX.sub('', s).strip()
    # curated PDF: 확장자만 제거하고 나머지는 보존
    if s.lower().endswith('.pdf'):
        return s[:-4].strip()
    # arXiv 형식(2607.19497)일 때만 버전 접미를 벗긴다 —
    # 임의 문자열에서 끝의 v+숫자를 벗기면 다른 id 를 훼손한다.
    if re.match(r'^\d{4}\.\d{4,5}(v\d+)?$', s, re.I):
        s = _VERSUF.sub('', s)
    return s


def collect_ids(obj, keys=('arxiv_id', 'paper_id', 'id')):
    """중첩 JSON 에서 논문 id 를 재귀 수집해 정규화한 집합으로."""
    out = set()

    def walk(o):
        if isinstance(o, dict):
            for k in keys:
                v = o.get(k)
                if isinstance(v, str):
                    n = norm_id(v)
                    if n:
                        out.add(n)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(obj)
    return out


if __name__ == '__main__':
    cases = [
        ('arxiv:2607.19497', '2607.19497'),
        ('arXiv:2607.19497v2', '2607.19497'),
        ('2607.19497', '2607.19497'),
        ('  2607.19497v11  ', '2607.19497'),
        ('https://arxiv.org/abs/2606.08569', '2606.08569'),
        ('FQ-110B', 'FQ-110B'),                 # 내부 id 는 훼손 금지
        ('some_paper_v2.pdf', 'some_paper_v2'),  # curated: 확장자만
        ('', ''),
        (None, ''),
    ]
    bad = 0
    for raw, want in cases:
        got = norm_id(raw)
        mark = 'ok  ' if got == want else 'FAIL'
        if got != want:
            bad += 1
        print('%s %-34r → %-16r (기대 %r)' % (mark, raw, got, want))
    print('\n%d/%d' % (len(cases) - bad, len(cases)))
    raise SystemExit(1 if bad else 0)
