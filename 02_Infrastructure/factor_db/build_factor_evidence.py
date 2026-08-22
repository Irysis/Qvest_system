# -*- coding: utf-8 -*-
"""build_factor_evidence.py — 팩터 실측 근거 환류 (2026-08-21 신설, 도훈 지시).

왜 있나 (실측 근거):
  factor_registry.json 373 팩터 중 `evidence_tier` 키를 가진 항목이 **0건**인데,
  .cache/conditional_ic_matrix.csv 에는 **327 팩터의 IC 실측**이 앉아 있었다.
  측정은 했는데 원장으로 돌아오지 않는 환류 단절 — 그래서 다음 라운드의 팩터 선택이
  근거 없이 이뤄지고, "331 전수 소진" 같은 판정이 원장에 흔적을 남기지 못했다.

★설계 결정 3개 (전부 기존 계약을 지키기 위한 것)

  1) **원장을 고치지 않고 사이드카를 쓴다.**
     factor_registry.json 은 jsonlite round-trip 시 13,100줄 전면 reformat 이 나는
     구조다([[reference-factor-onboarding-interface]] — add_factor 가 라인 타겟 append
     를 쓰는 이유). 373 항목에 필드를 심으려면 전면 재작성이 불가피하므로,
     비파괴 사이드카(06_Registry/factor_evidence.json)로 간다.

  2) **`evidence_tier` 를 채우지 않는다 — 다른 축이다.**
     strategy_registry.R:65 `VALID_EVIDENCE <- c("A","B","C")` 의 정의는
     "A=학술+실증+재현 / B=학술일부+초기 / C=가설" 로 **근거 출처·재현성 축**이다.
     IC 크기를 여기에 매핑하면 기존 라벨을 조용히 재정의하게 된다.
     ⇒ IC 축은 `ic_screen_tier` 라는 **별도 이름**으로 낸다. evidence_tier 는 그대로 빈다.

  3) **자본 주장 원천 차단.**
     measurement-graduation §3 은 rank_ic/icir 계열을 **ADVISORY** 로 못박았다
     (16후보 calibration 에서 rank_ic>=0.04 가 FLOW 거짓탈락 + NN/TECH 거짓통과).
     그래서 모든 레코드에 metric_type=screen_diagnostic · capital_claim=false 를 박는다.
     이 파일은 "무엇을 먼저 볼지" 를 정하는 우선순위이지 졸업 근거가 아니다.

★미측정 46건을 **빠뜨리지 않고 unmeasured 로 수록**한다.
  빈 값은 '없음'과 겉보기가 같다 — 목록에서 지우면 다음 소비자가 "전부 측정됐다"로 읽는다.
"""
import csv
import io
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("QM_ROOT") or os.path.abspath(os.path.join(HERE, "..", ".."))
REG = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")
IC = os.path.join(ROOT, ".cache", "conditional_ic_matrix.csv")
OUT = os.path.join(ROOT, "06_Registry", "factor_evidence.json")

# ── 절단선은 **여기 한 곳에서 선언**한다 (산출물에도 그대로 실어 사후 감사 가능하게).
#    근거: measurement-graduation 이 인용하는 advisory 선이 rank_ic 0.04.
#    그 아래를 둘로 가르는 0.02 는 실측 중앙값(0.0221) 근방 — 임의 선택임을 밝힌다.
THRESH = {
    "S1_abs_ic": 0.04,        # advisory 선 (measurement-graduation §3 인용선)
    "S2_abs_ic": 0.02,        # 실측 |ic_all| 중앙값 0.0221 근방 — 임의 절단(선언적)
    "S1_min_months": 240,     # 실측 n_months min 201 / median 314
    "S1_require_sign_agree": True,   # ic_all 과 recent_3y_icir 부호 일치 (288/327)
}


def _f(row, key):
    try:
        return float(row[key])
    except Exception:
        return None


def tier_of(ic_all, icir3, n_months):
    """ic_screen_tier 판정 — 우선순위 축이지 자본 게이트가 아니다."""
    if ic_all is None:
        return "unmeasured"
    a = abs(ic_all)
    if a >= THRESH["S1_abs_ic"]:
        sign_ok = (not THRESH["S1_require_sign_agree"]) or (
            icir3 is not None and ic_all * icir3 > 0)
        long_ok = (n_months or 0) >= THRESH["S1_min_months"]
        return "S1" if (sign_ok and long_ok) else "S2"
    if a >= THRESH["S2_abs_ic"]:
        return "S2"
    return "S3"


def build():
    reg = json.load(io.open(REG, encoding="utf-8"))
    if not os.path.exists(IC):
        sys.stderr.write("IC_MATRIX_MISSING %s\n" % IC)
        return None
    rows = {r["Factor_Name"]: r
            for r in csv.DictReader(io.open(IC, encoding="utf-8"))
            if r.get("Factor_Name")}

    # ★고아 검사 — IC 에는 있는데 원장에 없는 팩터가 있으면 둘 중 하나가 낡은 것이다.
    orphans = sorted(set(rows) - set(reg))

    recs = {}
    counts = {"S1": 0, "S2": 0, "S3": 0, "unmeasured": 0}
    for fid, meta in reg.items():
        life = meta.get("lifecycle") or {}
        r = rows.get(fid)
        ic_all = _f(r, "ic_all") if r else None
        icir3 = _f(r, "recent_3y_icir") if r else None
        nm = int(_f(r, "n_months") or 0) if r else 0
        t = tier_of(ic_all, icir3, nm)
        counts[t] += 1
        recs[fid] = {
            "ic_screen_tier": t,
            "ic_all": ic_all,
            "ic_bad": _f(r, "ic_bad") if r else None,
            "ic_good": _f(r, "ic_good") if r else None,
            # AX-001(방어형 조건부 평가)이 쓰는 축 — bad/good 격차를 버리지 않는다.
            "conditional_value": _f(r, "conditional_value") if r else None,
            "recent_3y_icir": icir3,
            "n_months": nm or None,
            "category": meta.get("category"),
            "direction": meta.get("direction"),
            "lifecycle_status": life.get("status"),
            "metric_type": "screen_diagnostic",
            "capital_claim": False,
        }

    obj = {
        "schema_version": "factor_evidence_v1",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "purpose": ("팩터 실측 IC 환류 사이드카. factor_registry.json 은 비파괴 유지 — "
                    "원장 round-trip 이 13,100줄 전면 reformat 을 내기 때문."),
        "axis_note": ("ic_screen_tier 는 factor_registry 의 evidence_tier(A/B/C = 학술·재현 축)와 "
                      "**다른 축**이다. evidence_tier 는 기계가 채우지 않는다."),
        "capital_note": ("전 레코드 metric_type=screen_diagnostic · capital_claim=false. "
                         "measurement-graduation §3 이 rank-IC 계열을 ADVISORY 로 규정 — "
                         "이 등급으로 graduation 을 주장하면 AX-002 위반."),
        "source": {
            "ic_matrix": os.path.relpath(IC, ROOT).replace("\\", "/"),
            "ic_matrix_mtime": time.strftime("%Y-%m-%dT%H:%M:%S",
                                             time.localtime(os.path.getmtime(IC))),
            "ic_rows": len(rows),
            "registry": os.path.relpath(REG, ROOT).replace("\\", "/"),
            "registry_n": len(reg),
        },
        "thresholds_declared": THRESH,
        "counts": counts,
        "orphans_ic_without_registry": orphans,
        "factors": recs,
    }
    tmp = OUT + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, OUT)      # 원자 교체 — 부분 기록본을 소비자가 읽지 않게
    return obj


def _load_out():
    try:
        return json.load(io.open(OUT, encoding="utf-8"))
    except Exception:
        return None


def is_stale():
    """산출물이 원천(IC 행렬)보다 낡았는가.

    ★파생물은 원천이 갱신되면 다시 만들어야 한다 — 그렇지 않으면 원장은 있는데
      내용이 과거를 가리키고, 소비자는 그걸 최신으로 읽는다(무음 낙후).
    """
    if not os.path.exists(OUT):
        return True
    if not os.path.exists(IC):
        return False               # 원천이 없으면 재빌드해도 나아지지 않는다
    return os.path.getmtime(OUT) < os.path.getmtime(IC)


def status_line():
    o = _load_out()
    if o is None:
        return ("FactorEvidence: UNREPORTED — 사이드카 부재/손상 "
                "(python 02_Infrastructure/factor_db/build_factor_evidence.py 로 생성)")
    c = o.get("counts", {})
    src = o.get("source", {})
    tail = " ★원천이 더 최신 — 재빌드 필요" if is_stale() else ""
    return ("FactorEvidence: %d팩터 S1=%d/S2=%d/S3=%d/미측정=%d · IC원천 %s (%d행)%s"
            % (len(o.get("factors", {})), c.get("S1", 0), c.get("S2", 0),
               c.get("S3", 0), c.get("unmeasured", 0),
               src.get("ic_matrix_mtime", "?"), src.get("ic_rows", 0), tail))


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--status-line" in args:
        print(status_line())
        sys.exit(0)
    if "--if-stale" in args and not is_stale():
        print("factor_evidence: up-to-date (원천보다 새로움) — skip")
        sys.exit(0)
    o = build()
    if o is None:
        sys.exit(3)
    print("factor_evidence: %d factors | %s | orphans=%d"
          % (len(o["factors"]), o["counts"], len(o["orphans_ic_without_registry"])))
