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

# ── (2026-11-11) 해석기 자기해결 — 배터리(run_all_hooks.sh)는 pandas · pyarrow 없는 시스템 파이썬으로 돈다.
#   없으면 venv 로 다시 실행한다(SKIP 하지 않는다 — SKIP 은 통과와 겉보기가 같다). 패턴 = data/test_qw_fund_v2_ingest.py.
try:
    import pandas as _pd_probe  # noqa: F401
    import pyarrow as _pa_probe  # noqa: F401
except ImportError:
    _venv = ""
    for _cand in (os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")),
                  os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe") if _cand else ""
        if _p and os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_QVEST_VENV_REEXEC") != "1":
        sys.exit(subprocess.call([_venv, "-X", "utf8", os.path.abspath(__file__)] + sys.argv[1:], env=dict(os.environ, _QVEST_VENV_REEXEC="1")))
    raise

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

    run_gate_cases()

    print(f"결과: PASS={PASS} FAIL={FAIL}")
    print(json.dumps({"test": "book_rebalance_preflight", "pass": PASS, "fail": FAIL,
                      "total": PASS + FAIL, "skipped": 0}, ensure_ascii=False))
    return 1 if FAIL else 0


# ── 러너 관문(--runner-gate) — 2026-11-06 도훈 지시 "daily_refresh 돌리는 프로세스는 빼버려" ──────────
#   러너가 적재를 그만두면서 생긴 자리를 이 모드가 검사로 막는다. 양방향으로 건다:
#   Ⓡ1 [음성 대조] 전부 sig 일 도달 + 앵커 일치 → OK(rc 0) · 마지막 줄 'OK sig=' (러너가 그 줄을 읽는다)
#   Ⓡ2 [위반] 컨센서스 한 계열만 sig 전에 멈춤 → BAD [reach] — 그 파일을 이름으로 짚고, 다른 계열은 OK(축마다 따로)
#   Ⓡ3 [위반] 팩터DB 앵커 ≠ sig → BAD [anchor]
#   Ⓡ4 [순환 차단] 벤치까지 같이 하루 낡음(전부 10-29 · 앵커 10-29) → BAD [benchmark]. 구 Gate B 처럼 sig 일을 벤치
#       최대값에서 구했다면 OK 가 났을 경우다 — sig 는 KRX 등록부에서 온다.
#   Ⓡ5 [미측정 ≠ 미달] 파손 계열 = UNREADABLE · 앵커 부재 = MISSING (OK 로 접지 않음) · skip 목록(ticker_map)은 재지 않음
#   Ⓡ6 [fail-closed] 등록부 부재 → BAD [calendar] · 사양에 runner_gate 없음 → rc 2
RG_AS_OF, RG_SIG = "2026-11-01", "2026-10-30"     # 2026-10-30(금) = KRX 등록부 기준 11-01 직전 거래일


def build_rg_root(tmp, *, data_max=RG_SIG, bench_end=RG_SIG, anchor=RG_SIG, lag_file=None,
                  corrupt=(), drop=(), registry=True, with_gate=True):
    days = lambda end: pd.bdate_range("2026-10-01", end).tolist()
    _wp(f"{tmp}/.cache/benchmark.parquet", pd.DataFrame({"Date": days(bench_end)}))
    for rel in (".cache/RAWDATA.parquet", ".cache/investor_stock/investor_all.parquet",
                ".cache/consensus/eps_1y.parquet", ".cache/consensus/op_profit_fy1.parquet",
                ".cache/universe_support/us_k200.parquet"):
        end = "2026-10-19" if lag_file and rel.endswith(lag_file) else data_max
        _wp(f"{tmp}/{rel}", pd.DataFrame({"Date": days(end)}))
    _wp(f"{tmp}/.cache/consensus/ticker_map.parquet", pd.DataFrame({"Ticker": ["A000020"], "Name": ["x"]}))
    _wp(f"{tmp}/.cache/factor_db/factor_db_202610.parquet", pd.DataFrame({"Date": pd.to_datetime([anchor])}))
    if registry:
        os.makedirs(f"{tmp}/06_Registry", exist_ok=True)
        shutil.copy(os.path.join(CODE_ROOT, "06_Registry", "krx_holidays.json"), f"{tmp}/06_Registry/krx_holidays.json")
    gate = {"date_col": "Date", "anchor": ".cache/factor_db/factor_db_{sig_ym}.parquet",
            "sig_reach": [{"glob": ".cache/RAWDATA.parquet"},
                          {"glob": ".cache/investor_stock/investor_all.parquet"},
                          {"glob": ".cache/consensus/*.parquet", "skip": ["ticker_map.parquet"]},
                          {"glob": ".cache/universe_support/*.parquet"}]}
    spec = {"book_id": "BOOK_RG", "strategy_id": "FIXTURE", "inputs": [], "overlays": []}
    if with_gate:
        spec["runner_gate"] = gate
    os.makedirs(f"{tmp}/02_Infrastructure/book", exist_ok=True)
    with open(f"{tmp}/02_Infrastructure/book/rebalance_spec.json", "w", encoding="utf-8") as fh:
        json.dump({"schema": "book_rebalance_spec_v1", "specs": [spec]}, fh, ensure_ascii=False)
    for rel in drop:
        os.remove(f"{tmp}/{rel}")
    for rel in corrupt:
        with open(f"{tmp}/{rel}", "wb") as fh:
            fh.write(b"not a parquet")
    return tmp


def run_rg(tmp, as_json=True):
    env = dict(os.environ, QM_ROOT=tmp.replace("\\", "/"), PYTHONUTF8="1")
    cmd = [sys.executable, CHECKER, "--book-id", "BOOK_RG", "--as-of", RG_AS_OF, "--runner-gate"]
    r = subprocess.run(cmd + (["--json"] if as_json else []), capture_output=True, text=True,
                       encoding="utf-8", env=env, cwd=tmp)
    if not as_json:
        return r.returncode, (r.stdout.strip().splitlines() or [""])[-1]
    try:
        return r.returncode, json.loads(r.stdout)
    except Exception:
        return r.returncode, {"_raw": (r.stdout + r.stderr)[-300:]}


def bad_checks(p, tag=None):
    return [c for c in p.get("checks", []) if not c["ok"] and (tag is None or c["check"] == tag)]


def run_gate_cases():
    print("=== 러너 관문(--runner-gate) ===")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t)
        rc, p = run_rg(t)
        rc2, last = run_rg(t, as_json=False)
        if rc == 0 and p.get("verdict") == "OK" and p.get("sig_date") == RG_SIG and rc2 == 0 \
                and last.startswith(f"OK sig={RG_SIG}"):
            ok(f"Ⓡ1 전부 도달 → OK · 마지막 줄 '{last[:40]}'")
        else:
            ng(f"Ⓡ1 신선한데 막혔다: rc={rc} {p.get('verdict')} sig={p.get('sig_date')} last={last[:80]} {p.get('_raw','')}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, lag_file="op_profit_fy1.parquet")
        rc, p = run_rg(t)
        b = bad_checks(p, "reach")
        eps_ok = any(c["ok"] and "eps_1y" in c["detail"] for c in p.get("checks", []))
        if rc == 1 and len(b) == 1 and "op_profit_fy1" in b[0]["detail"] and eps_ok:
            ok("Ⓡ2 한 계열만 낡음 → BAD [reach] 그 파일만 짚음 · 다른 계열 OK(축마다 따로)")
        else:
            ng(f"Ⓡ2 계열 낡음 처리 오류: rc={rc} bad={[c['detail'] for c in b]} eps_ok={eps_ok}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, anchor="2026-10-29")
        rc, p = run_rg(t)
        if rc == 1 and bad_checks(p, "anchor") and not bad_checks(p, "reach"):
            ok("Ⓡ3 앵커 ≠ sig → BAD [anchor]")
        else:
            ng(f"Ⓡ3 앵커 불일치 미검출: rc={rc} {[c['detail'] for c in bad_checks(p)]}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, data_max="2026-10-29", bench_end="2026-10-29", anchor="2026-10-29")
        rc, p = run_rg(t)
        if rc == 1 and bad_checks(p, "benchmark") and p.get("sig_date") == RG_SIG:
            ok("Ⓡ4 벤치까지 같이 낡음 → BAD [benchmark] (sig 는 등록부 10-30 — 벤치 최대값에 끌려가지 않음)")
        else:
            ng(f"Ⓡ4 순환 미차단: rc={rc} sig={p.get('sig_date')} {[c['detail'] for c in bad_checks(p)]}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, corrupt=(".cache/consensus/eps_1y.parquet",), drop=(".cache/factor_db/factor_db_202610.parquet",))
        rc, p = run_rg(t)
        unr = [c for c in bad_checks(p, "reach") if "UNREADABLE" in c["detail"]]
        mis = [c for c in bad_checks(p, "anchor") if "MISSING" in c["detail"]]
        tmap = [c for c in p.get("checks", []) if "ticker_map" in c["detail"]]
        if rc == 1 and unr and mis and not tmap:
            ok("Ⓡ5 파손 = UNREADABLE · 앵커 부재 = MISSING · skip 목록(ticker_map) 미측정")
        else:
            ng(f"Ⓡ5 미측정 처리 오류: rc={rc} unr={len(unr)} mis={len(mis)} ticker_map={len(tmap)}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, registry=False)
        rc, p = run_rg(t)
        if rc == 1 and bad_checks(p, "calendar") and p.get("verdict") == "BAD":
            ok("Ⓡ6 등록부 부재 → BAD [calendar] (판정 불가 = 통과 아님)")
        else:
            ng(f"Ⓡ6 등록부 부재 처리 오류: rc={rc} {p.get('verdict')} {p.get('_raw','')}")
    with tempfile.TemporaryDirectory() as t:
        build_rg_root(t, with_gate=False)
        rc, p = run_rg(t)
        if rc == 2:
            ok("Ⓡ6 사양에 runner_gate 없음 → rc 2 (무엇을 잴지 모르면 통과시키지 않는다)")
        else:
            ng(f"Ⓡ6 runner_gate 부재가 rc={rc}")


if __name__ == "__main__":
    sys.exit(main())
