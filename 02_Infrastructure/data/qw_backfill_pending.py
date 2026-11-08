"""qw_backfill_pending.py — 신규 상장 보충 수급 대기열(.cache/qw_backfill_pending.json)의 판독 · 정리.

왜(2026-11-08 · BUILD_20261108.md §1): ops/qw_datakey_sync.ps1 이 DB DATA_Key 끝에 새 종목을 붙이면, 그 종목의 상장일부터
  지금까지의 값이 그 DB에 없다. DB의 평소 수급 창(드라이버 앵커 = 출력 최신일 + 1)은 그 과거를 다시 받지 않으므로,
  붙인 날 기록한 '보충 시작일'을 다음 수급 한 번에 -FromOverride 로 넘겨 그 창을 전 종목 그대로 다시 받는다
  (적재기는 받은 창의 날짜를 전 종목 통째로 교체한다 — 일부 종목만 담은 사본 DB 적재 금지 · PLAN §5.2 ⑦ 정정).

사용(data/qw_updatefile_unattended.sh 가 부른다):
  overrides --pending P --only A,B
      → 'A=YYYYMMDD,B=YYYYMMDD' (Time Series DB · from 이 있는 것만 · 없으면 빈 줄)
  clear --pending P --state S --since YYYY-MM-DDTHH:MM:SS --books A,B
      → 드라이버 상태(.cache/qw_refresh_state.json)에서 ts >= since 인 DB(= 이번 수급에서 목표일 완료)만 대기열에서 지운다.
종료 코드: overrides 는 늘 0(판독 실패 = 보충 없음 · 평소 창) · clear 는 0 정상 · 1 오류.
"""
from __future__ import annotations

import argparse
import json
import os
import sys


def _load(path: str) -> dict:
    with open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def overrides(pending: str, only: str) -> int:
    try:
        d = _load(pending)
    except Exception as e:  # noqa: BLE001
        print(f"[backfill] 대기열 판독 실패({e}) — 보충 없음", file=sys.stderr)
        print("")
        return 0
    out = []
    for k in [x for x in only.split(",") if x]:
        v = d.get(k) or {}
        f = str(v.get("from") or "")
        if (v.get("layout") or "ts") == "ts" and len(f) == 8 and f.isdigit():
            out.append(f"{k}={f}")
    print(",".join(out))
    return 0


def clear(pending: str, state: str, since: str, books: str) -> int:
    d = _load(pending)
    st = _load(state)
    done, keep = [], []
    for k in [x for x in books.split(",") if x]:
        ts = str((st.get(k) or {}).get("ts") or "")
        (done if ts >= since and k in d else keep).append(k)
    for k in done:
        d.pop(k, None)
    tmp = pending + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, pending)
    print(f"[backfill] 완료로 지움: {','.join(done) or '-'} · 남김: {','.join(keep) or '-'}")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("overrides"); o.add_argument("--pending", required=True); o.add_argument("--only", required=True)
    c = sub.add_parser("clear"); c.add_argument("--pending", required=True); c.add_argument("--state", required=True)
    c.add_argument("--since", required=True); c.add_argument("--books", required=True)
    a = ap.parse_args()
    try:
        sys.exit(overrides(a.pending, a.only) if a.cmd == "overrides" else clear(a.pending, a.state, a.since, a.books))
    except Exception as e:  # noqa: BLE001
        print(f"[backfill] ERROR: {e}")
        sys.exit(1)
