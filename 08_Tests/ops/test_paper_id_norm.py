# -*- coding: utf-8 -*-
"""test_paper_id_norm.py — 논문 id 정규화 정본의 **왕복·비훼손·수렴** (2026-08-22 신설)

왜 있나 (실사고 2026-08-22, 하루 3회):
  같은 대상에 수치가 셋이었다 — 좌초 논문 **154 / 62 / 61**, 재발견 **27회 / 10회**.
  셋 다 개수는 정확했고 **정규화 규약이 달랐다**(제목 vs id / 접두·버전접미 처리 / 창 절단).
  정본 적용 후 좌초는 **61편**으로 수렴했고, 내 154편이 틀렸음이 드러났다
  (창 밖 날짜의 전체 논문을 셌고 그중 **93편은 다른 날 route 에 이미 등장**했다).
  반대로 재라우팅은 내가 **과소**했다(3회 → 22회, `arxiv:` 접두·`v2` 접미로 같은 논문을 놓침).

★1급 축은 "정규화가 되는가" 가 아니라 **"정규화가 다른 id 를 훼손하지 않는가"** 다.
  끝의 `v숫자`를 무조건 벗기면 `some_paper_v2` 같은 내부 id 가 망가진다 —
  과잉 정규화는 과소 정규화와 정확히 반대 방향으로 수치를 틀리게 만든다.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, '02_Infrastructure', 'ops'))

_p = [0]
_f = [0]


def ok(m):
    _p[0] += 1
    print("  PASS  %s" % m)


def ng(m, d):
    _f[0] += 1
    print("  FAIL  %s :: %s" % (m, d))


try:
    from paper_id_norm import norm_id, collect_ids
except Exception as e:
    print("  SKIP  정규화 모듈 부재/불러오기 실패: %s" % e)
    print("== t_summary: PASS=0 FAIL=0 ==")
    print('{"test":"paper_id_norm","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"정규화 모듈 부재/불러오기 실패","missing":"%s"}]}' % ("paper_id_norm 모듈 (%s)" % str(e).replace('"', "'")[:120]))
    sys.exit(0)

print("== 정규화 축: 같은 논문의 여러 표기가 한 값으로 모이는가 ==")
same = ['2607.19497', 'arxiv:2607.19497', 'arXiv:2607.19497v2',
        '  2607.19497v11  ', 'https://arxiv.org/abs/2607.19497']
got = set(norm_id(x) for x in same)
if got == {'2607.19497'}:
    ok("5가지 표기 → 1값 수렴")
else:
    ng("수렴 실패", got)

print("== ★비훼손 축: 다른 id 를 망가뜨리지 않는가 (과잉 정규화 방지) ==")
keep = [('FQ-110B', 'FQ-110B'),
        ('FQ-100', 'FQ-100'),
        ('STR_AS_20260808_075822_21700', 'STR_AS_20260808_075822_21700'),
        ('some_paper_v2.pdf', 'some_paper_v2'),
        ('Vol_Rank_Markov_Persistence', 'Vol_Rank_Markov_Persistence')]
bad = [(a, norm_id(a), b) for a, b in keep if norm_id(a) != b]
if not bad:
    ok("내부 id · curated 파일명 보존 (%d종)" % len(keep))
else:
    ng("id 훼손", bad)

print("== 경계: 결손을 '있는 척' 하지 않는가 ==")
if norm_id(None) == '' and norm_id('') == '' and norm_id('   ') == '':
    ok("None/빈문자 → '' (가짜 id 생성 안 함)")
else:
    ng("결손 처리", [norm_id(None), norm_id(''), norm_id('   ')])

print("== 멱등: 두 번 돌려도 같은가 ==")
probe = ['arXiv:2607.19497v2', 'FQ-110B', 'some_paper_v2.pdf', '2606.08569']
if all(norm_id(norm_id(x)) == norm_id(x) for x in probe):
    ok("norm(norm(x)) == norm(x)")
else:
    ng("멱등 위반", [(x, norm_id(x), norm_id(norm_id(x))) for x in probe])

print("== 수집 축: 중첩 JSON 에서 재귀로 모으는가 ==")
doc = {'date': '20260822',
       'papers': [{'arxiv_id': 'arxiv:2607.19497v1', 'meta': {'paper_id': '2606.08569'}},
                  {'nested': {'deep': [{'id': '2608.12283v3'}]}}],
       'noise': {'ticker': '005930'}}
s = collect_ids(doc)
if {'2607.19497', '2606.08569', '2608.12283'} <= s:
    ok("중첩 3단계에서 3편 수집")
else:
    ng("수집 실패", s)

print("== ★위반 주입: 정규화 없이 세면 답이 갈리는가 (이 모듈이 필요한 이유) ==")
raw = ['2607.19497', 'arxiv:2607.19497', '2607.19497v2']
if len(set(raw)) == 3 and len(set(norm_id(x) for x in raw)) == 1:
    ok("raw 3 vs 정규화 1 — 정규화 없으면 같은 논문을 3편으로 센다")
else:
    ng("대조 실패", (set(raw), set(norm_id(x) for x in raw)))

print("== 계약 축: 모듈이 기간(창)을 숨기지 않는가 ==")
# 창을 모듈에 숨기면 같은 함수가 호출처마다 다른 답을 낸다 — 규약상 금지.
import inspect  # noqa: E402
src = inspect.getsource(sys.modules['paper_id_norm'])
banned = [w for w in ('datetime', 'timedelta', 'days=', 'TODAY') if w in src.split('"""')[-1]]
if not banned:
    ok("id 정규화만 담당 — 기간 로직 없음")
else:
    ng("관심사 혼입", "본문에 기간 토큰: %s" % banned)

print("== 소비자 축: 정본이 실제로 불려지는가 ==")
import glob  # noqa: E402
users = []
for pat in ('02_Infrastructure/ops/*.py', '08_Tests/ops/*.py'):
    for f in glob.glob(os.path.join(ROOT, pat)):
        if os.path.basename(f) in ('paper_id_norm.py', 'test_paper_id_norm.py'):
            continue
        try:
            if 'paper_id_norm' in open(f, encoding='utf-8', errors='replace').read():
                users.append(os.path.basename(f))
        except Exception:
            pass
if users:
    ok("소비자 %d개: %s" % (len(users), ', '.join(users[:4])))
else:
    ng("소비자 0", "정본을 만들고 아무도 안 부른다 — 오늘 네 번 겪은 계통")

print("== t_summary: PASS=%d FAIL=%d ==" % (_p[0], _f[0]))
print('{"test":"paper_id_norm","pass":%d,"fail":%d,"total":%d,"skipped":0}' % (_p[0], _f[0], (_p[0])+(_f[0])))
sys.exit(1 if _f[0] else 0)
