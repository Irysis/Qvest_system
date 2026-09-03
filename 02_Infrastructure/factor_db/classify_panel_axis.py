#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# classify_panel_axis.py — 팩터가 **횡단면인가 시계열인가**를 기계로 판정 (2026-09-01)
#
# 왜 필요한가:
#   registry 373종에는 종목별 노출(cross_sectional)과 시장수준 상태(time_series)가
#   구분 없이 섞여 있다. 그래서 42종이 "IC 가 없다"는 한 덩어리로 보였는데, 실제로는
#   ①구조적으로 횡단면 IC 가 불가한 것(VIX·신용스프레드·시장낙폭) ②생산자가 없는 것
#   ③진짜 결함이 뒤섞여 있었다. 축을 안 갈라 놓으면 어느 쪽도 수리할 수 없다.
#
#   실측 발견(2026-09-01): M31_Breadth_Mom 은 parquet 에 값이 있는데 **전 종목 동일값**이다.
#   시장 브레드스를 종목 축으로 배출한 것이고, 상수라 횡단면 IC 가 정의되지 않아 조용히
#   빠져 있었다. 이름이나 계열로는 안 잡히고 **배출된 값의 횡단면 분산**으로만 잡힌다.
#
# 소비자: rf_factor_arms.R(B1 = cross_sectional 만) · B5 국면 입력(time_series)
#
# ★출력은 파생 사이드카다. factor_registry.json 을 건드리지 않는다 —
#   그 파일은 373엔트리 13k줄이라 전체 round-trip 이 diff·동시성에 치명적이라고
#   add_factor.R 이 명시했다. 사이드카는 언제든 재생성 가능하다.
#
# 실행: python 02_Infrastructure/factor_db/classify_panel_axis.py [--quiet]
#       (멱등 — 반복 호출해도 같은 결과. 무인 tick 이 매일 불러도 무해)
# ==============================================================================
import io
import json
import os
import re
import sys
import time

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
FDB = os.path.join(ROOT, ".cache", "factor_db")
OUT = os.path.join(ROOT, "06_Registry", "factor_panel_axis.json")

# 시장수준 원천 — 종목 축이 존재할 수 없다
MARKET_SOURCES = {"macro", "macro_fred"}
# 횡단면 분산 판정에 쓸 표본 월 수. 한 달만 보고 판정하면 그 달만 상수인 경우를 놓친다
# (범위를 선언하기 전에 세지 말 것 — 저장소 반복 교훈).
SAMPLE_MONTHS = 12


def main(argv):
    quiet = "--quiet" in argv
    try:
        import pandas as pd
    except ImportError:
        print("[panel_axis] pandas 부재 — venv python 으로 실행할 것", file=sys.stderr)
        return 1

    reg_p = os.path.join(FDB, "factor_registry.json")
    reg = json.loads(io.open(reg_p, "rb").read().decode("utf-8"))

    # ★엄격한 패턴 — 백업 사본(factor_db_202605_PRE_m08rebuild.parquet 등)이 섞이면
    #   낡은 스냅샷으로 축을 판정하게 된다. 빌더가 쓰는 정규식과 같은 것을 쓴다.
    months = sorted(f for f in os.listdir(FDB) if re.match(r"^factor_db_\d{6}\.parquet$", f))
    if not months:
        print("[panel_axis] 월간 parquet 부재", file=sys.stderr)
        return 1
    sample = months[-SAMPLE_MONTHS:]

    # 팩터별: 관측된 달 수 + 그 달들에서의 횡단면 distinct 최댓값
    seen = {}
    for fn in sample:
        df = pd.read_parquet(os.path.join(FDB, fn), columns=["Factor_Name", "Raw_Value"])
        g = df.groupby("Factor_Name")["Raw_Value"].nunique()
        for name, nu in g.items():
            cur = seen.setdefault(str(name), {"months": 0, "max_nuniq": 0})
            cur["months"] += 1
            cur["max_nuniq"] = max(cur["max_nuniq"], int(nu))

    out = {}
    tally = {}
    for fid, meta in reg.items():
        meta = meta or {}
        ds = str(meta.get("data_source") or "")
        obs = seen.get(fid)

        # ★판정 순서 = **관측 우선, 선언은 폴백**. 처음엔 data_source 를 먼저 봤는데
        #   MA03_Rate_Sensitivity 는 data_source=macro 인데 실제 배출은 종목별 2,464개 값이었다
        #   (금리 민감도 = 종목별 베타). 선언은 원천이 무엇인지 말할 뿐 산출 축을 말하지 않는다.
        #   감사 항목은 재도출이어야 한다 — 진술은 증거가 아니다.
        if obs is None:
            if ds in MARKET_SOURCES:
                axis = "time_series"
                basis = "배출 0행 + data_source=%s(시장수준 원천) — 선언 기반 판정" % ds
                ev = {"observed_months": 0, "sample_months": len(sample), "by": "declaration"}
            else:
                # 축을 **관측으로** 정할 수 없다 — 지어내지 않고 unknown 으로 둔다.
                axis, basis = "unknown", "표본 %d개월 배출 0행 — 관측으로 축을 정할 수 없다" % len(sample)
                ev = {"observed_months": 0, "sample_months": len(sample)}
        elif obs["max_nuniq"] <= 1:
            axis = "time_series"
            basis = "배출은 되지만 표본 전 구간에서 **전 종목 동일값**(횡단면 분산 0) — 종목 축이 아니다"
            ev = {"observed_months": obs["months"], "max_cross_sectional_distinct": obs["max_nuniq"]}
        else:
            axis, basis = "cross_sectional", "횡단면 분산 실재(관측)"
            ev = {"observed_months": obs["months"], "max_cross_sectional_distinct": obs["max_nuniq"]}

        out[fid] = {"panel_axis": axis, "basis": basis, "category": meta.get("category"),
                    "data_source": ds or None, "evidence": ev}
        tally[axis] = tally.get(axis, 0) + 1

    doc = {
        "schema": "factor_panel_axis_v1",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "producer": "02_Infrastructure/factor_db/classify_panel_axis.py",
        "note": ("팩터의 패널 축 판정(파생 사이드카). cross_sectional = 종목별 노출 → B1 컴포짓 재료. "
                 "time_series = 시장수준 상태 → B5 오버레이 국면 입력. unknown = 배출 0행이라 관측으로 "
                 "정할 수 없음(추측하지 않는다 — 배출 격차 경보가 표면화한다). "
                 "★factor_registry.json 은 건드리지 않는다(13k줄 round-trip 위험)."),
        "sample_months": [m.replace("factor_db_", "").replace(".parquet", "") for m in sample],
        "tally": tally,
        "factors": out,
    }
    io.open(OUT, "wb").write(json.dumps(doc, ensure_ascii=False, indent=1).encode("utf-8"))
    if not quiet:
        print("[panel_axis] %d종 판정 → %s" % (len(out), os.path.relpath(OUT, ROOT)))
        print("  " + " · ".join("%s %d" % (k, v) for k, v in sorted(tally.items())))
        ts = sorted(k for k, v in out.items() if v["panel_axis"] == "time_series")
        print("  time_series: " + ", ".join(ts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
