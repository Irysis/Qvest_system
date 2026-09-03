#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# test_rf_pick_key.py — 논문 소비 판정 키의 **정본성** 양방향 검사 (2026-09-01)
#
# 무엇을 지키는가:
#   rf_next_paper_pick.py 는 "이미 손댄 논문"을 큐에서 걸러낸다. 그 판정 키는
#   **발행 키와 같은 술어(pid_of)** 로 만들어져야 한다. 판정 쪽에서 키를 다시 만들면
#   정규화 전후가 어긋나 소비한 논문이 큐 상단에 영원히 남는다.
#
# 실사고 2026-09-01:
#   큐 항목이 paper_key='axv:2505.20608'(접두) · id='2505.20608' 를 함께 들고 있는데
#   판정은 `arxiv_id or paper_key or key` 순으로 **접두형**을 집었고, 원장에는 pid_of 가
#   정규화한 '2505.20608' 이 적혀 있었다. 결과: 소비 7초 뒤 같은 논문을 다시 집어
#   충실구현을 재실행했고(2505.20608), 2608.23944 는 4회 반복 측정됐다. 큐 74건이 굶었다.
#   ★버전 접미도 같은 계통이다 — 'axv:cond-mat/0410079v1' vs 'cond-mat/0410079'.
#
# 실행: python 08_Tests/reinforcement/test_rf_pick_key.py
# 부작용 없음 — 읽기만 한다.
# ==============================================================================
import io
import json
import os
import subprocess
import sys

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OPS = os.path.join(ROOT, "02_Infrastructure", "ops")
if OPS not in sys.path:
    sys.path.insert(0, OPS)

FAIL = []
OK = []


def ok(msg):
    OK.append(msg)
    print("  OK   " + msg)


def ng(msg):
    FAIL.append(msg)
    print("  FAIL " + msg)


def _load(p, default):
    try:
        return json.loads(io.open(p, "rb").read().decode("utf-8"))
    except Exception:
        return default


# ── 준비 ──────────────────────────────────────────────────────────────────────
try:
    import rf_next_paper_pick as PICK
    from research_pool_predicates import pid_of
except Exception as e:                                    # pragma: no cover
    print("  FAIL import 실패: %s" % e)
    sys.exit(1)

if not hasattr(PICK, "probe_keys"):
    # 중첩 함수로 되돌아가면 검사가 가드를 부를 수 없다 — 그 자체가 결함이다.
    ng("probe_keys 가 모듈 수준에 없다 — 가드를 양방향으로 잴 수 없는 상태")
    sys.exit(1)

led = _load(os.path.join(ROOT, "06_Registry", "reinforce_ledger_l1.json"), {"entries": []})
done = {str(e.get("paper_key") or "") for e in (led.get("entries") or []) if e.get("paper_key")}
sk = _load(os.path.join(ROOT, "06_Registry", "replication_skiplist.json"), {"entries": []})
skip = {str(e.get("paper_key")) for e in (sk.get("entries") or []) if e.get("status") != "revoked"}

# ── ① 계약 (end-to-end): picker 가 소비분·스킵분을 내놓지 않는다 ──────────────
out = subprocess.run([sys.executable, os.path.join(OPS, "rf_next_paper_pick.py")],
                     capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
line = (out.stdout or "").strip().splitlines()
picked = json.loads(line[-1]) if line else {}
pk = str(picked.get("paper_key") or "")

if picked.get("error") in ("no_item_with_url",) or not pk:
    # 큐가 비었거나 전부 소비된 상태 — 계약 위반은 아니다(러너가 무동작으로 물러난다)
    ok("큐에 남은 항목 없음 — 계약 검사 무해 통과(%s)" % picked.get("error", "empty"))
else:
    if pk in done:
        ng("소비 누출 — picker 가 원장에 있는 %s 를 다시 냈다" % pk)
    else:
        ok("소비 판정 — 선택 %s 는 원장 %d건에 없다" % (pk, len(done)))
    if pk in skip:
        ng("스킵 누출 — picker 가 스킵리스트의 %s 를 다시 냈다" % pk)
    else:
        ok("스킵 판정 — 선택 %s 는 스킵 %d건에 없다" % (pk, len(skip)))

# ── ② 양성 대조 (합성 주입): 구판 파생은 놓치고 현행은 잡는다 ────────────────
# ★픽스처는 실제 포맷 배치를 그대로 흉내낸다 — 필드 이름을 틀리면 검사가 조용히 죽는다
#   (이 검사를 쓰면서 {'title':..} 만 준 첫 판이 정확히 그렇게 죽었다).
FIX = [
    ("접두형", {"title": "x", "id": "2505.20608",
                "paper_key": "axv:2505.20608", "source": "arxiv"}, "2505.20608"),
    ("접두+버전", {"title": "x", "id": "cond-mat/0410079",
                   "paper_key": "axv:cond-mat/0410079v1", "source": "arxiv"}, "cond-mat/0410079"),
]


def _old_probe(o, key):
    """구판 파생 — 판정 쪽에서 키를 다시 만들던 형태(위반 주입용)."""
    return {str(o.get("arxiv_id") or o.get("paper_key") or key or "")}


for tag, item, canon in FIX:
    dict_key = item["id"]
    assert str(pid_of(item, warn=False)) == canon, "픽스처가 낡음(%s)" % tag

    cur = PICK.probe_keys(item, dict_key)
    old = _old_probe(item, dict_key)

    if canon in cur:
        ok("현행 파생이 정본 키를 포함(%s → %s)" % (tag, canon))
    else:
        ng("현행 파생이 정본 키를 놓쳤다(%s: %s)" % (tag, sorted(cur)))

    if canon in old:
        # 구판이 이 형태를 이미 잡는다면 위반 주입이 실패한 것 — 검사기가 낡았다.
        ng("양성 대조 미발화(%s) — 구판 파생도 정본 키를 냈다. 픽스처가 실제 결함 형태가 아니다" % tag)
    else:
        ok("양성 대조 발화(%s) — 구판 파생 %s 는 정본 키를 놓친다" % (tag, sorted(old)))

print("합계: 통과 %d · 실패 %d" % (len(OK), len(FAIL)))
print('{"test":"rf_pick_key","pass":%d,"fail":%d,"total":%d}' % (len(OK), len(FAIL), len(OK) + len(FAIL)))
sys.exit(1 if FAIL else 0)
