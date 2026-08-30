#!/usr/bin/env python
"""test_book_rebalance_preflight.py — BOOK 리밸 사전점검의 양방향 검증.

배경 (2026-08-30): 이 검사기는 "낡음을 잡는다"고 주장한다. 그 주장을 **양방향**으로 건다.
통과만 재는 검사기는 방어선이 아니다 — 이 저장소가 반복해 겪은 부류(양성 대조 없는 계기).

계약 (각 분기가 실제로 갈리는가):
  ① [음성 대조] 전부 신선 → GO (rc 0). 정상 리밸을 막지 않는다.
  ② [위반 주입] data-mode 입력이 관용을 넘어 낡음 → BLOCK + STALE (rc 1)
  ③ [위반 주입] decision-mode 패널에 as_of 행이 없음 → BLOCK + STALE
        (AE 침묵 재사용 병의 픽스처. 직전 달 행이 있어도 '신선'으로 읽으면 안 된다)
  ④ [위반 주입] anchor-mode 앵커가 기대 sig_date 와 다름 → BLOCK + STALE
  ⑤ [미측정 ≠ 미달] 파일 부재 → MISSING · 판독 불가 → UNREADABLE (OK 로 접지 않는다)
  ⑥ [축 C] expect_alive 인데 0회 발화 → DEAD **이고 BLOCK(rc 1)**. 죽은 축은 전략
        구현이 덜 된 것이므로 넘어가지 않는다(도훈 지시 2026-08-30). 음성 대조 = 발화하면 GO.
  ⑦ [축 C] expect_alive:false 인데 발화 → REVIVED + BLOCK (구판 회귀 감시)
  ⑧ [fail-closed] 사양에 없는 book_id → rc 2 (GO 로 접지 않는다)
  ⑨ [경계] 낡은 입력의 안내가 **소관 이관**이지 적재 명령이 아니다 — 데이터 적재는
        데이터 리프레시 쪽 소관이고 리밸 스킬은 쓰기만 한다.

방식: 임시 루트에 픽스처를 깔고 QM_ROOT 로 검사기를 실제 실행한다(재구현 금지).
실행: python 08_Tests/book/test_book_rebalance_preflight.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# ★self-first 앵커 (r_portability 금칙 ④-b): 코드 루트는 이 파일 기준으로 잡는다.
#   worktree 에서 돌 때 main 구판 검사기를 재는 사고를 막는다.
_SELF = os.path.dirname(os.path.abspath(__file__))
CODE_ROOT = os.path.abspath(os.path.join(_SELF, "..", ".."))
if not os.path.exists(os.path.join(CODE_ROOT, "02_Infrastructure", "book",
                                   "book_rebalance_preflight.py")):
    CODE_ROOT = os.environ.get("QM_ROOT", CODE_ROOT).replace("\\", "/")
CHECKER = os.path.join(CODE_ROOT, "02_Infrastructure", "book", "book_rebalance_preflight.py")

PASS, FAIL = 0, 0


def ok(m):
    global PASS
    print(f"  [PASS] {m}")
    PASS += 1


def ng(m):
    global FAIL
    print(f"  [FAIL] {m}")
    FAIL += 1


AS_OF = "2026-09-01"
SIG_DATE = "2026-08-28"


def _wp(path, df):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pq.write_table(pa.Table.from_pandas(df, preserve_index=False), path)


def build_root(tmp, *, data_max="2026-08-28", decision_rows=("2026-08-01", "2026-09-01"),
               anchor=SIG_DATE, m4_dead=False, legacy_revived=False,
               drop=(), corrupt=()):
    """픽스처 루트. 인자를 바꿔 각 위반을 주입한다.

    ★benchmark 는 항상 신선하게 둔다 — 거래일 캘린더 권위라 이걸 낡히면 sig_date 판정
      자체가 불가해져 검사기가 rc 2(환경 오류)로 끝난다. 그건 '낡음 미검출'이 아니라
      다른 분기다. data_max 는 **소비 데이터**(RAWDATA)만 움직인다.
    """
    bdays = pd.bdate_range("2026-08-03", "2026-08-28").tolist()
    _wp(f"{tmp}/.cache/benchmark.parquet", pd.DataFrame({"Date": bdays}))
    _wp(f"{tmp}/.cache/RAWDATA.parquet",
        pd.DataFrame({"Date": pd.bdate_range("2026-07-01", data_max).tolist()}))

    dec = pd.to_datetime(list(decision_rows))
    n = len(dec)
    # m4 패널: fire 조건 컬럼 포함. m4_dead=True 면 bocpd 팔이 0회 발화.
    mass = [0.9] * n if legacy_revived else [0.2] * n
    runlen = [20.0] * n if legacy_revived else [9.0] * n
    _wp(f"{tmp}/m4.parquet", pd.DataFrame({
        "Date": dec,
        "Cash_Pct_lag": [0.0] * n,
        "decay_signal": [0.0] * n if m4_dead else [0.8] * n,
        "decay_R2": [0.3] * n,
        "bocpd_short_run_mass_lag": mass,
        "bocpd_expected_runlen_lag": runlen,
        "weight_str1715": [1.0] * n,
    }))
    _wp(f"{tmp}/ae.parquet", pd.DataFrame({"decision_date": dec, "fire_seq": [1] * n}))
    _wp(f"{tmp}/alpha.parquet", pd.DataFrame({"Date": dec, "regime_state": ["CRISIS"] * n}))
    _wp(f"{tmp}/.cache/factor_db/factor_db_202608.parquet",
        pd.DataFrame({"Date": pd.to_datetime([anchor])}))

    spec = {"schema": "book_rebalance_spec_v1", "specs": [{
        "book_id": "BOOK_TEST", "strategy_id": "FIXTURE", "kind": "factor_strategy", "layer": 1,
        "runner": {"cmd": "echo run {as_of}", "weights_out": "x", "manifest_out": "y"},
        "inputs": [
            {"id": "rawdata", "path": ".cache/RAWDATA.parquet", "date_col": "Date",
             "mode": "data", "max_lag_days": 5, "producer": "p",
             "produced_by_runner": False, "refresh_owner": "테스트 적재소관"},
            {"id": "ae_panel", "path": "ae.parquet", "date_col": "decision_date",
             "mode": "decision", "producer": "p", "produced_by_runner": True},
            {"id": "m4_panel", "path": "m4.parquet", "date_col": "Date",
             "mode": "decision", "producer": "p", "produced_by_runner": True},
            {"id": "alpha_panel", "path": "alpha.parquet", "date_col": "Date",
             "mode": "decision", "producer": "p", "produced_by_runner": True},
            {"id": "factor_db", "path": ".cache/factor_db/factor_db_{sig_ym}.parquet",
             "date_col": "Date", "mode": "anchor", "producer": "p", "produced_by_runner": True},
        ],
        "overlays": [
            {"id": "m4_decay", "panel": "m4_panel", "date_col": "Date",
             "fire_expr": "decay_signal >= 0.7 & decay_R2 >= 0.05", "expect_alive": True},
            {"id": "legacy_guard", "panel": "m4_panel", "date_col": "Date",
             "fire_expr": "bocpd_short_run_mass_lag >= 0.60 & bocpd_expected_runlen_lag >= 12",
             "expect_alive": False, "note": "구판 회귀 감시"},
        ],
        "post_checks": [],
    }]}
    os.makedirs(f"{tmp}/02_Infrastructure/book", exist_ok=True)
    with open(f"{tmp}/02_Infrastructure/book/rebalance_spec.json", "w", encoding="utf-8") as fh:
        json.dump(spec, fh, ensure_ascii=False)

    for rel in drop:
        p = f"{tmp}/{rel}"
        if os.path.exists(p):
            os.remove(p)
    for rel in corrupt:
        with open(f"{tmp}/{rel}", "wb") as fh:
            fh.write(b"not a parquet")
    return tmp


def run(tmp, book_id="BOOK_TEST"):
    env = dict(os.environ, QM_ROOT=tmp.replace("\\", "/"))
    r = subprocess.run([sys.executable, CHECKER, "--book-id", book_id,
                        "--as-of", AS_OF, "--json"],
                       capture_output=True, text=True, env=env, cwd=tmp)
    try:
        return r.returncode, json.loads(r.stdout)
    except Exception:
        return r.returncode, {"_raw": r.stdout + r.stderr}


def verdict_of(payload, section, _id):
    for x in payload.get(section, []):
        if x["id"] == _id:
            return x["verdict"]
    return None


def main():
    if not os.path.exists(CHECKER):
        print(f"XX 검사기 부재: {CHECKER}")
        return 9

    # ① 음성 대조 — 전부 신선하면 GO
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t))
        if rc == 0 and p.get("verdict") == "GO":
            ok("① 전부 신선 → GO (정상 리밸을 막지 않는다)")
        else:
            ng(f"① 신선한데 막혔다: rc={rc} verdict={p.get('verdict')} {p.get('_raw','')[:160]}")

    # ② data-mode 낡음 주입
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, data_max="2026-07-10"))
        if rc == 1 and verdict_of(p, "inputs", "rawdata") == "STALE":
            ok("② data 입력 낡음 → BLOCK + STALE")
        else:
            ng(f"② 낡음을 못 잡음: rc={rc} rawdata={verdict_of(p,'inputs','rawdata')}")

    # ③ decision-mode as_of 행 부재 (AE 침묵 재사용 병)
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, decision_rows=("2026-07-01", "2026-08-01")))
        if rc == 1 and verdict_of(p, "inputs", "ae_panel") == "STALE":
            ok("③ as_of 행 부재 → STALE (직전 달 존재를 신선함으로 읽지 않는다)")
        else:
            ng(f"③ 직전 달만 있는데 통과: ae_panel={verdict_of(p,'inputs','ae_panel')}")

    # ④ anchor 불일치
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, anchor="2026-08-14"))
        if rc == 1 and verdict_of(p, "inputs", "factor_db") == "STALE":
            ok("④ 앵커 불일치 → STALE")
        else:
            ng(f"④ 앵커 불일치를 못 잡음: factor_db={verdict_of(p,'inputs','factor_db')}")

    # ⑤ 미측정 ≠ 미달 — 부재는 MISSING, 파손은 UNREADABLE
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, drop=("ae.parquet",)))
        if rc == 1 and verdict_of(p, "inputs", "ae_panel") == "MISSING":
            ok("⑤ 파일 부재 → MISSING (OK 로 접지 않음)")
        else:
            ng(f"⑤ 부재 판정 오류: {verdict_of(p,'inputs','ae_panel')}")
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, corrupt=("ae.parquet",)))
        if rc == 1 and verdict_of(p, "inputs", "ae_panel") == "UNREADABLE":
            ok("⑤ 파손 → UNREADABLE ('못 읽음'과 '낡음'을 구분)")
        else:
            ng(f"⑤ 파손 판정 오류: {verdict_of(p,'inputs','ae_panel')}")

    # ⑥ 축 C — expect_alive 인데 0회 발화 → DEAD **이고 차단**
    #   (도훈 지시 2026-08-30: "죽은 축이 있으면 전략 구현이 제대로 안 된 거니까
    #    넘어가지 말아야 해." 구판은 경고로 뒀고, 그게 m4 BOCPD 271개월 0회 발화를
    #    '정상'으로 통과시킨 구조다. 판정만 재고 rc 를 안 재면 계약이 반쪽이다.)
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, m4_dead=True))
        if verdict_of(p, "overlays", "m4_decay") == "DEAD" and rc == 1 and p.get("verdict") == "BLOCK":
            ok("⑥ 0회 발화 팔 → DEAD + BLOCK (경고로 넘기지 않는다)")
        else:
            ng(f"⑥ 죽은 팔 처리 오류: verdict={verdict_of(p,'overlays','m4_decay')} rc={rc} 판정={p.get('verdict')}")
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, m4_dead=False))
        if verdict_of(p, "overlays", "m4_decay") == "OK" and rc == 0:
            ok("⑥ 발화하는 팔 → OK + GO (음성 대조 — 살아 있으면 막지 않는다)")
        else:
            ng(f"⑥ 살아 있는 팔을 막음: {verdict_of(p,'overlays','m4_decay')} rc={rc}")

    # ⑦ 축 C — 죽어 있어야 할 구판 조건이 부활 → REVIVED **이고 차단**
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, legacy_revived=True))
        if verdict_of(p, "overlays", "legacy_guard") == "REVIVED" and rc == 1:
            ok("⑦ 구판 조건 부활 → REVIVED + BLOCK (회귀 감시가 차단까지 간다)")
        else:
            ng(f"⑦ 부활 처리 오류: {verdict_of(p,'overlays','legacy_guard')} rc={rc}")

    # ⑨ [경계] 낡은 입력의 안내가 **리프레시 명령이 아니라 소관 이관**인가
    #   리밸 스킬이 적재 방법을 안내하면 경계가 무너지고 같은 값을 두 곳에서 만들게 된다.
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t, data_max="2026-07-10"))
        rec = next((x for x in p.get("inputs", []) if x["id"] == "rawdata"), {})
        if rec.get("refresh_owner") and "manual_cmd" not in rec:
            ok("⑨ 낡은 입력은 refresh_owner 로 이관 (적재 명령을 안내하지 않는다)")
        else:
            ng(f"⑨ 경계 위반 — 리밸 스킬이 적재를 안내한다: {sorted(rec.keys())}")

    # ⑧ fail-closed — 사양에 없는 book_id
    with tempfile.TemporaryDirectory() as t:
        rc, p = run(build_root(t), book_id="BOOK_NOPE")
        if rc == 2:
            ok("⑧ 미등재 book_id → rc 2 (GO 로 접지 않는다)")
        else:
            ng(f"⑧ 미등재 book_id 가 rc={rc} — fail-closed 아님")

    print(f"결과: PASS={PASS} FAIL={FAIL}")
    print(json.dumps({"test": "book_rebalance_preflight", "pass": PASS, "fail": FAIL,
                      "total": PASS + FAIL, "skipped": 0}, ensure_ascii=False))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
