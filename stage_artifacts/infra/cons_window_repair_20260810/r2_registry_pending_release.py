# -*- coding: utf-8 -*-
"""
r2_registry_pending_release.py — FQ-218 (C) 조건부 alias 선언 = **해제 예약** 상태 전환

★r1(선언 즉시 해제)은 틀렸고 배터리가 그것을 잡았다. 기록으로 남긴다:
  r1 을 적용하자 test_emission_identity_axes(N1/N2) 와
  test_factor_dedup_consumption(new_5pairs_collapsed) 이 빨개졌다. 이유가 정확하다 —
  **선별은 코드가 아니라 저장 parquet 를 소비한다.** 코드는 수리됐지만 factor_db 의
  303개월(200106..202608)은 아직 결함값이라 C10 은 여전히 C01 과 비트동일이다.
  그 상태에서 alias 를 풀면 두 팩터가 같은 풀에서 **이중 투표**한다 — 선언이
  막으려던 바로 그 피해다. 검사기를 고칠 게 아니라 상태 전환을 고쳐야 한다.

그래서 이번 전환은 '해제'가 아니라 **'해제 예약'** 이다:
  - role/canonical/cluster/deprecated_for_selection = **유지** (선별 보호 유지)
  - defect.revisit_on 조건이 충족됐음을 **실측 증거와 함께 기록**
  - 해제를 막고 있는 것(재빌드)과 해제 시 할 일을 명시
  - 재빌드 완료 후 별도 단계에서 role -> independent

경계: C11->M25(DUPC-046), C09->C01 은 이 결함과 무관 — 손대지 않는다.
"""
import io, json, sys, os

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
P = os.path.join(ROOT, "02_Infrastructure/factor_db/factor_registry.json")
APPLY = "--apply" in sys.argv
TODAY = "2026-08-10"

# ★줄끝은 바이트로 확인한다 — text 모드 읽기는 CRLF 를 조용히 LF 로 바꿔
#   왕복이 '동일'로 보이게 만들고, 디스크에는 전 줄이 바뀐 유령 diff 를 남긴다.
RAW = open(P, "rb").read()
NL = b"\r\n" if RAW.count(b"\r\n") > 0 else b"\n"
print("[fmt] 원본 줄끝 = %s (CRLF=%d, bare LF=%d)"
      % ("CRLF" if NL == b"\r\n" else "LF",
         RAW.count(b"\r\n"), RAW.count(b"\n") - RAW.count(b"\r\n")))
reg = json.loads(RAW.decode("utf-8"))

def dump_bytes(d):
    s = json.dumps(d, ensure_ascii=False, indent=2) + "\n"
    return s.replace("\n", NL.decode()).encode("utf-8")

if dump_bytes(reg) != RAW:
    a, b = RAW, dump_bytes(reg)
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    print("[STOP] 형식 왕복 불일치 @%d — 쓰면 전면 재직렬화" % i)
    print("  orig %r\n  rt   %r" % (a[max(0,i-60):i+60], b[max(0,i-60):i+60]))
    sys.exit(2)
print("[ok] 형식 왕복 **바이트** 동일 — 줄끝/들여쓰기 보존 확인")

REBUILD = ("factor_db 재빌드 303개월 (200106..202608, 월당 62.7초 실측 단가로 약 317분). "
           "저장 parquet 가 갱신되기 전까지 C10/C13 의 저장값은 여전히 결함값이다.")
EVID = {
    "measured_at": TODAY, "fq": "FQ-218",
    "method": ("git HEAD(수리 전) 판본과 작업트리(수리 후) 판본을 별도 env 에 source 해 "
               "같은 입력·같은 sig_date 8개월(2006/2010/2011/2014/2018/2019/2022/2024)로 실행 대조"),
    "window_definition": ("연속-런(run) 붕괴 후 최신 N 분기 릴리스. 런 경계 = 값이 패널에 처음 "
                          "나타난 날 = 가용일(실측: 값 변경 100%가 4/6/9/12월 첫 영업일, "
                          "월말 0%, 주말 0건 — 한국 분기 법정기한 이후). "
                          "stale 소급 차단 상한 = n_take*130일, 최소 2 릴리스."),
    "artifacts": [
        "stage_artifacts/infra/cons_window_repair_20260810/p3_design_agg.csv",
        "stage_artifacts/infra/cons_window_repair_20260810/p6_bound_validate.csv",
        "stage_artifacts/infra/cons_window_repair_20260810/v1_pair_identity.csv",
    ],
    "test": "08_Tests/factor_db/test_cons_window_quarterly.R (15 PASS / 0 FAIL / 0 SKIP)",
}

def stage(fname, canon, remeasured):
    d = reg[fname]["dedup"]
    assert d.get("role") == "alias" and d.get("canonical") == canon, \
        "%s 현 선언이 기대와 다름: role=%r canonical=%r" % (fname, d.get("role"), d.get("canonical"))
    d["release_pending"] = {
        "status": "condition_met_awaiting_rebuild",
        "condition_text": d.get("defect", {}).get("revisit_on"),
        "condition_met": True,
        "code_repaired_at": TODAY,
        "repaired_by": "FQ-218 — compute_consensus.R .cons_quarters() (창 단위: 관측 행 -> 분기 릴리스)",
        "remeasured_on_repaired_code": remeasured,
        "blocked_by": REBUILD,
        "unblock_action": ("재빌드 완료 후: (1) 저장 parquet 에서 비트동일 해소를 재확인 "
                           "(2) role -> independent, deprecated_for_selection -> false "
                           "(3) %s.aliases 에서 %s 제거 (4) 사유·직전 선언 보존" % (canon, fname)),
        "why_not_released_now": ("선별(drop_alias_factors)은 코드가 아니라 **저장 parquet** 를 소비한다. "
                                 "저장값이 아직 비트동일인 상태에서 alias 를 풀면 C01/C10(및 C04/C13)이 "
                                 "같은 풀에서 이중 투표한다 — 이 선언이 막으려던 바로 그 피해다. "
                                 "2026-08-10 즉시 해제를 시도했을 때 test_emission_identity_axes(N1/N2)와 "
                                 "test_factor_dedup_consumption(new_5pairs_collapsed)이 이를 검거했다."),
        "evidence": EVID,
    }
    print("[stage] %s: alias(%s) 유지 + release_pending 기록 (조건 충족, 재빌드 대기)" % (fname, canon))

stage("C10_SUE_Persistence", "C01_SUE",
      {"rho_before": 1.0, "rho_after_mean": 0.5405,
       "max_abs_diff_before": 0.0, "max_abs_diff_after": 37837.5481,
       "frac_eq_latest_before": 1.0, "frac_eq_latest_after": 0.0,
       "window_distinct_before": 1, "window_distinct_after": 4,
       "n_rows_before": 806, "n_rows_after": 295, "n_months": 8,
       "verdict_on_repaired_code": "NOT_DUPLICATE",
       "coverage_note": ("행수 감소는 결손이 아니라 정직화다 — 상한 안에 분기 릴리스가 2개 미만인 "
                         "종목(커버리지가 끊겨 값이 캐리포워드되던 종목)은 값을 만들지 않는다. "
                         "구 코드는 그들에게 C01 복제값을 주고 있었다.")})

stage("C13_Revision_Breadth_3m", "C04_ESBR",
      {"rho_before": 1.0, "rho_after_mean": 0.5701,
       "max_abs_diff_before": 0.0, "max_abs_diff_after": 1.7363,
       "frac_eq_latest_before": 1.0, "frac_eq_latest_after": 0.0,
       "window_distinct_before": 1, "window_distinct_after": 3,
       "n_rows_before": 1230, "n_rows_after": 416, "n_months": 8,
       "verdict_on_repaired_code": "NOT_DUPLICATE",
       "naming_note": ("이름의 '3m' 은 원 구현이 관측을 월간이라 가정한 데서 왔다. 원천 esbr 은 "
                       "분기 릴리스이므로 수리 후 실제 창은 3분기(약 9개월)다. 이름 재사용 금지 "
                       "규약상 개명하지 않는다 — 재빌드 시 definition 으로 명시할 사안.")})

# C15 — alias 선언 없음(죽은 배출로 분류). 수리 기록만 추가, 역할 변경 없음.
c15 = reg["C15_Forecast_Error_Trend"]
c15.setdefault("dedup", {})["release_pending"] = {
    "status": "dead_emission_repaired_awaiting_rebuild",
    "code_repaired_at": TODAY, "repaired_by": "FQ-218 (.cons_quarters)",
    "prior_defect": ("구 구현은 sue[1]-sue[2] 를 **연속 행**(같은 분기값 2벌)에서 취해 전 종목 0. "
                     "횡단면 sd 0 -> Z 전건 NA -> 소비면 도달 0행 (FQ-210 축3a, 50/50월 죽은 배출)."),
    "remeasured_on_repaired_code": {
        "sd_before": 0.0, "sd_after_mean": 426.91,
        "frac_zero_before": 1.0, "frac_zero_after": 0.0,
        "n_distinct_before": 1, "n_distinct_after_mean": 239,
        "n_rows_before": 806, "n_rows_after": 239, "n_months": 8},
    "blocked_by": REBUILD,
    "unblock_action": "재빌드 후 저장 parquet 에서 sd>0 재확인 + definition 을 분기 창으로 명시",
    "evidence": EVID,
}
print("[stage] C15_Forecast_Error_Trend: 죽은 배출 수리 기록 (역할 변경 없음)")

guard = {
    "C10.role": reg["C10_SUE_Persistence"]["dedup"]["role"],
    "C13.role": reg["C13_Revision_Breadth_3m"]["dedup"]["role"],
    "C11.role": reg["C11_Earnings_Streak"]["dedup"]["role"],
    "C11.aliases": reg["C11_Earnings_Streak"]["dedup"]["aliases"],
    "C01.aliases": reg["C01_SUE"]["dedup"]["aliases"],
    "C04.aliases": reg["C04_ESBR"]["dedup"]["aliases"],
}
print("[guard]", json.dumps(guard, ensure_ascii=False))
assert guard["C10.role"] == "alias" and guard["C13.role"] == "alias", "선별 보호가 풀렸다"
assert guard["C11.aliases"] == ["M25_Earnings_Mom_Streak"], "C11->M25 를 건드렸다"
assert "C09_Earnings_Surprise_Sq" in guard["C01.aliases"], "C09 선언이 사라졌다"
assert "C10_SUE_Persistence" in guard["C01.aliases"], "C10 alias 가 조기 해제됐다"
assert "C13_Revision_Breadth_3m" in guard["C04.aliases"], "C13 alias 가 조기 해제됐다"

new = dump_bytes(reg)
if not APPLY:
    print("\n[dry-run] --apply 없음. %d -> %d bytes" % (len(RAW), len(new))); sys.exit(0)

open(P, "wb").write(new)
chk = json.loads(open(P, "rb").read().decode("utf-8"))
assert len(chk) == len(reg), "팩터 수 변동 — 삭제 발생"
for f in ("C10_SUE_Persistence", "C13_Revision_Breadth_3m", "C15_Forecast_Error_Trend"):
    assert chk[f]["dedup"]["release_pending"]["code_repaired_at"] == TODAY
assert chk["C10_SUE_Persistence"]["dedup"]["role"] == "alias"
assert chk["C11_Earnings_Streak"]["dedup"]["aliases"] == ["M25_Earnings_Mom_Streak"]
b2 = open(P, "rb").read()
print("[applied] 재읽기 검증 통과. 팩터 %d (불변) · CRLF=%d bareLF=%d"
      % (len(chk), b2.count(b"\r\n"), b2.count(b"\n") - b2.count(b"\r\n")))
