# -*- coding: utf-8 -*-
"""
r1_registry_alias_release.py — FQ-218 (C) 조건부 alias 선언 해제

2026-08-09 에 등재된 C10->C01 / C13->C04 alias 선언은 **조건부**였다:
  revisit_on: ".cons_history() 가 분기 관측으로 축약되도록 수리되면 이 alias 선언은
               무효다 — 재측정 후 재선언할 것. 수리 전까지만 유효."

그 조건이 충족됐고(2026-08-10 수리), 재측정으로 비트동일이 풀린 것을 확인했다.
따라서 선언을 **해제**한다 — 삭제가 아니라 상태 전환 + 사유·직전 상태 보존.

경계: C11->M25(DUPC-046) 와 C09->C01 은 이 결함과 무관하므로 **건드리지 않는다**.
      (C09 = sign(sue)*sue^2 = 단조변환 재등록. 창 수리와 독립적으로 여전히 alias)

★쓰기 전 형식 왕복 검증: 이 저장소는 공유 원장을 재직렬화하며 형식이 어긋나
  전면 diff 가 나 "순수 추가 확인" 규약이 무력해진 전례가 있다. 그래서 먼저
  load->dump 가 원본과 **바이트 동일**인지 확인하고, 아니면 쓰지 않고 중단한다.
"""
import io, json, sys, os, datetime

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
P = os.path.join(ROOT, "02_Infrastructure/factor_db/factor_registry.json")
APPLY = "--apply" in sys.argv
TODAY = "2026-08-10"

# ★줄끝은 **바이트로** 확인한다. io.open(text) 은 universal-newline 으로 CRLF 를
#   조용히 LF 로 바꿔 읽으므로, 텍스트끼리 비교하면 왕복이 '동일'로 보이고 정작
#   디스크에는 18,276줄이 전부 바뀐 유령 diff 가 난다(2026-08-10 실제로 한 번 냈다).
RAW = open(P, "rb").read()
NL = b"\r\n" if RAW.count(b"\r\n") > 0 else b"\n"
print("[fmt] 원본 줄끝 = %s (CRLF=%d, bare LF=%d)"
      % ("CRLF" if NL == b"\r\n" else "LF",
         RAW.count(b"\r\n"), RAW.count(b"\n") - RAW.count(b"\r\n")))
orig = RAW.decode("utf-8")
reg = json.loads(orig)

def dump_bytes(d):
    s = json.dumps(d, ensure_ascii=False, indent=2) + "\n"
    return s.replace("\n", NL.decode()).encode("utf-8")

def dump(d):
    return dump_bytes(d).decode("utf-8")

# ── 형식 왕복 검증 (쓰기 자격 시험) — 바이트 대조 ──────────────────────────
if dump_bytes(reg) != RAW:
    a, b = RAW, dump_bytes(reg)
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    print("[STOP] 형식 왕복 불일치 — 이 writer 로 쓰면 전면 재직렬화가 난다.")
    print("  len orig=%d rt=%d  first diff @%d" % (len(a), len(b), i))
    print("  orig: %r" % a[max(0, i-60):i+60])
    print("  rt  : %r" % b[max(0, i-60):i+60])
    sys.exit(2)
print("[ok] 형식 왕복 **바이트** 동일 — indent=2 / ensure_ascii=False / 줄끝 보존 / 끝 개행")

EVID = {
    "measured_at": TODAY,
    "fq": "FQ-218",
    "method": "git HEAD(수리 전) 판본과 작업트리(수리 후) 판본을 별도 env 에 source 해 "
              "같은 입력·같은 sig_date 8개월(2006/2010/2011/2014/2018/2019/2022/2024)로 실행 대조",
    "report": "stage_artifacts/infra/cons_window_repair_20260810/v1_pair_identity.csv",
}

def release(fname, canon, cluster, new_def, pair_evid):
    e = reg[fname]
    d = e["dedup"]
    assert d.get("role") == "alias" and d.get("canonical") == canon, \
        "%s 의 현 선언이 기대와 다름: %r" % (fname, d.get("role"))
    prior = {k: d[k] for k in ("role", "canonical", "cluster", "deprecated_for_selection",
                               "mechanism", "reason", "defect", "evidence", "consumption_rule")
             if k in d}
    prior["definition"] = e.get("definition")
    # 상태 전환 — 삭제가 아니라 역할 변경 + 직전 상태 보존
    d["role"] = "independent"
    d["deprecated_for_selection"] = False
    d.pop("canonical", None)
    d.pop("cluster", None)
    d.pop("mechanism", None)
    d.pop("defect", None)
    d.pop("consumption_rule", None)
    d["reason"] = ("2026-08-09 alias 선언은 무력 창(inert window) 결함에 **조건부**였다. "
                   "2026-08-10 FQ-218 이 창 단위를 관측 행 -> 분기 릴리스로 수리해 "
                   "revisit_on 조건이 충족됐고, 재측정에서 비트동일이 풀렸다. 선언 해제.")
    d["resolved"] = {
        "status": "alias_declaration_released",
        "released_at": TODAY,
        "released_by": "FQ-218 (.cons_quarters 창 수리)",
        "revisit_on_condition_met": True,
        "condition_text": prior.get("defect", {}).get("revisit_on"),
        "remeasured": pair_evid,
        "evidence": EVID,
        "prior_declaration": prior,
        "note": ("해제는 '중복이 아니다'의 실측 확인이지 알파 자격 판정이 아니다. "
                 "C10/C13 의 선별 자격은 재빌드 후 별도 판정 대상이다."),
    }
    e["definition"] = new_def
    # canonical 측 aliases 목록에서 제거 (직전 목록은 canonical 측에도 기록)
    cd = reg[canon]["dedup"]
    before = list(cd.get("aliases", []))
    cd["aliases"] = [a for a in before if a != fname]
    cd.setdefault("resolved_history", []).append({
        "released": fname, "at": TODAY, "by": "FQ-218",
        "aliases_before": before, "aliases_after": list(cd["aliases"]),
        "reason": "조건부 alias 선언 해제 — 창 수리 후 비트동일 해소",
        "evidence": pair_evid,
    })
    print("[release] %s: alias(%s) -> independent | %s.aliases %s -> %s"
          % (fname, canon, canon, before, cd["aliases"]))

release(
    "C10_SUE_Persistence", "C01_SUE", "DUPC-005",
    "Mean SUE over the last 4 quarterly consensus releases (run-collapsed, "
    "max lookback 520d, min 2 releases). PEAD persistence proxy. "
    "★창 단위는 관측 행이 아니라 분기 릴리스다 — 원천 sue 는 일간 캐리포워드이므로 "
    "행 기반 창은 항등변환이 된다 (FQ-218, 2026-08-10).",
    {"rho_before": 1.0, "rho_after_mean": 0.5405,
     "max_abs_diff_before": 0.0, "max_abs_diff_after": 37837.5481,
     "frac_eq_latest_before": 1.0, "frac_eq_latest_after": 0.0,
     "n_months": 8, "verdict": "NOT_DUPLICATE"})

release(
    "C13_Revision_Breadth_3m", "C04_ESBR", "DUPC-045",
    "Mean ESBR over the last 3 quarterly consensus releases (run-collapsed, "
    "max lookback 390d, min 2 releases). Smoothed revision breadth. "
    "★이름의 '3m' 은 원 구현이 관측을 월간이라 가정한 데서 왔다 — 원천 esbr 은 분기 "
    "릴리스이므로 실제 창은 3분기(약 9개월)다. 이름 재사용 금지 규약상 개명하지 않고 "
    "정의로 명시한다 (FQ-218, 2026-08-10).",
    {"rho_before": 1.0, "rho_after_mean": 0.5701,
     "max_abs_diff_before": 0.0, "max_abs_diff_after": 1.7363,
     "frac_eq_latest_before": 1.0, "frac_eq_latest_after": 0.0,
     "n_months": 8, "verdict": "NOT_DUPLICATE"})

# C15 — alias 선언은 없었으나(죽은 배출로 분류) 정의가 창 단위를 명시하지 않아
# 같은 오독을 부른다. 정의 정밀화 + 수리 기록만 추가한다(역할 변경 없음).
c15 = reg["C15_Forecast_Error_Trend"]
c15_prior_def = c15.get("definition")
c15["definition"] = ("Latest quarterly SUE release minus the previous quarterly release "
                     "(run-collapsed, max lookback 260d, requires 2 releases). SUE direction. "
                     "★구 구현은 연속 **행** 차분이라 전 종목 0 -> 횡단면 sd 0 -> 소비면 도달 "
                     "0행이었다 (FQ-210 축3a 죽은 배출, FQ-218 에서 수리).")
c15.setdefault("dedup", {})
c15["dedup"]["resolved"] = {
    "status": "dead_emission_repaired",
    "released_at": TODAY, "released_by": "FQ-218 (.cons_quarters 창 수리)",
    "prior_definition": c15_prior_def,
    "remeasured": {"sd_before": 0.0, "sd_after_mean": 426.91,
                   "frac_zero_before": 1.0, "frac_zero_after": 0.0,
                   "n_distinct_before": 1, "n_distinct_after_mean": 239, "n_months": 8},
    "evidence": EVID,
    "note": "재빌드 전까지 factor_db 저장값은 여전히 결함값(전 종목 0)이다 — 이 기록은 "
            "코드 수리 사실이지 저장 데이터 상태가 아니다.",
}
print("[note] C15_Forecast_Error_Trend: 정의 정밀화 + 수리 기록 (역할 변경 없음)")

# ── 경계 확인: 건드리면 안 되는 것들이 그대로인가 ───────────────────────────
guard = {
    "C11_Earnings_Streak.dedup.role": reg["C11_Earnings_Streak"]["dedup"]["role"],
    "C11_Earnings_Streak.dedup.aliases": reg["C11_Earnings_Streak"]["dedup"]["aliases"],
    "C09_in_C01_aliases": "C09_Earnings_Surprise_Sq" in reg["C01_SUE"]["dedup"]["aliases"],
}
print("[guard]", json.dumps(guard, ensure_ascii=False))
assert guard["C11_Earnings_Streak.dedup.role"] == "canonical"
assert guard["C11_Earnings_Streak.dedup.aliases"] == ["M25_Earnings_Mom_Streak"]
assert guard["C09_in_C01_aliases"] is True, "C09 alias 선언이 사라졌다 — 범위 초과"

new = dump_bytes(reg)
if not APPLY:
    print("\n[dry-run] --apply 없음. 쓰지 않음.")
    print("  기존 %d bytes -> 신규 %d bytes" % (len(RAW), len(new)))
    sys.exit(0)

open(P, "wb").write(new)   # 바이트로 쓴다 — 텍스트 모드는 줄끝을 다시 바꾼다
# 재읽기 검증
chk = json.loads(io.open(P, encoding="utf-8").read())
assert chk["C10_SUE_Persistence"]["dedup"]["role"] == "independent"
assert chk["C13_Revision_Breadth_3m"]["dedup"]["role"] == "independent"
assert "C10_SUE_Persistence" not in chk["C01_SUE"]["dedup"]["aliases"]
assert "C09_Earnings_Surprise_Sq" in chk["C01_SUE"]["dedup"]["aliases"]
assert "C13_Revision_Breadth_3m" not in chk["C04_ESBR"]["dedup"]["aliases"]
assert chk["C11_Earnings_Streak"]["dedup"]["aliases"] == ["M25_Earnings_Mom_Streak"]
assert len(chk) == len(reg), "팩터 수 변동 — 삭제가 일어났다"
print("[applied] 재읽기 검증 통과. 팩터 수 %d (불변)" % len(chk))
