#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_ast_specs.py — WT-D20260802_001 / FQ-073
AST v1.1 팩터 스펙 생성 (2개 방언 동시 산출).

★발견 (인프라 결함, 본 라운드 실측): Step 2 컴파일러(ast_compile.R)와 Step 3 정적검증기
  (ast_verify.py)의 노드 방언이 서로 다르다 — 번역기 부재.
    compile 방언 : {"type":"op","op":"X","args":[...],"params":{...}}
                   leaf {"type":"leaf","class":...,"source":...,"field":...,"contract":{...}}
    verify  방언 : {"op":"X","children":[...], <params flat>}
                   leaf {"leaf":"STORED_SCORE","group_id":...,"provenance":{...}, ...}
  따라서 본 스크립트가 **단일 논리 정의**에서 두 방언을 생성해 정합을 보증한다
  (수기로 두 번 쓰면 어긋난 채 통과할 수 있다 — AST 계층의 목적 자체를 무력화).
"""
import json, os

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts/WT_D20260802_001")
PANEL_REL = "stage_artifacts/WT_D20260802_001/fq073_export_exposure_chapter.parquet"

META = json.load(open(os.path.join(OUT, "fq073_export_exposure_chapter_meta.json"),
                      encoding="utf-8"))

# ── 단일 논리 정의 (dialect-neutral) ─────────────────────────────────────────
# L      = STORED_SCORE 리프 (firm-month 수출노출 USD)
# SEC    = rawdata Sector 리프 (CS_NEUTRALIZE 그룹)
# G      = LOG(L) − LOG(TS_LAG(L,12))        계절성 제거 로그 YoY 성장
# S      = G − TS_MEAN(G,12)                  자기 12M 성장평균 대비 서프라이즈
L = ("leaf_stored",)
SEC = ("leaf_sector",)


def op(name, args, **params):
    return ("op", name, args, params)


G = op("SUB", [op("LOG", [L]), op("LOG", [op("TS_LAG", [L], k=12, _unit="m")])])
S = op("SUB", [G, op("TS_MEAN", [G], window=12)])

# ★ast_verify 실측 검거 (2026-08-02, 1차 F4 = FAIL_LOOKAHEAD):
#   rawdata Sector 의 availability 규칙은 t1(T+1) — 신호일 당일 관측 Sector 는
#   그 신호일에 아직 가용하지 않다(avail_ts 2026-08-01 > decision_ts 2026-07-31).
#   기존 hand-rolled 러너(run_fq073_export.R:300-305)는 score_date=Date 로 당일 Sector 를
#   그대로 merge 한다 = 동일 위반이 정적검증 없이는 드러나지 않았다.
#   𝒪 안에서의 정직한 수정 = TS_LAG(Sector, 1일).
SEC_LAGGED = op("TS_LAG", [SEC], k=1, _unit="d")

FACTORS = {
    # PRIMARY — 서프라이즈 (레벨은 이미 가격 반영이라는 메커니즘 가설의 직접 표현)
    "F1_export_surprise": op("CS_ZSCORE", [op("CS_WINSORIZE", [S], p=0.02)]),
    # 대조군 1 — 성장 레벨 (서프라이즈가 레벨보다 나은가?)
    "F2_export_yoy_level": op("CS_ZSCORE", [op("CS_WINSORIZE", [G], p=0.02)]),
    # 대조군 2 — 성장 가속 (3개월 변화)
    "F3_export_accel": op("CS_ZSCORE", [op("CS_WINSORIZE", [op("TS_DELTA", [G], k=3)], p=0.02)]),
    # 대조군 3 — 섹터중립 서프라이즈 (FQ-066/067 sector-rotation negative 대비 증분 분리)
    "F4_export_surprise_secneutral": op(
        "CS_ZSCORE", [op("CS_NEUTRALIZE", [op("CS_WINSORIZE", [S], p=0.02), SEC_LAGGED])]),
}

# ── 방언 1: ast_compile.R ────────────────────────────────────────────────────
COMPILE_LEAF_STORED = {
    "type": "leaf", "class": "STORED_SCORE", "source": "stored_panel",
    "field": "export_exposure_usd",
    "contract": {
        "path": PANEL_REL,
        "value_col": "value",
        "store_build_hash": META["store_build_hash"],
        "generator_code_path": META["generator_code_path"],
        "generated_at": META["generated_at"],
        # ★정직 선언: 본 패널은 신규 리서치 패널로 production 대응 코드 경로가 존재하지 않는다.
        #   true 로 적는 것은 허위 주장이므로 false 로 둔다 (결과: ast_verify FAIL_CONTRACT —
        #   본 라운드의 AST 계층 발견 #2, ast_leaf_table_bugs.jsonl 적립).
        "production_parity_verified": False,
        "avail_offset_days": None,   # 패널 내 avail_ts 컬럼이 권위 (암묵 0 금지 규약 충족)
    },
}
COMPILE_LEAF_SECTOR = {"type": "leaf", "class": "FIELD", "source": "rawdata", "field": "Sector"}


def to_compile(node):
    if node is L:
        return COMPILE_LEAF_STORED
    if node is SEC:
        return COMPILE_LEAF_SECTOR
    _, name, args, params = node
    out = {"type": "op", "op": name, "args": [to_compile(a) for a in args]}
    p = {k: v for k, v in params.items() if not k.startswith("_")}
    if p:
        out["params"] = p
    return out


# ── 방언 2: ast_verify.py ────────────────────────────────────────────────────
VERIFY_LEAF_STORED = {
    "leaf": "STORED_SCORE",
    # ★group_id 없음 — ast_field_map_v0.json 58 그룹에 관세청/무역통계 리프가 부재.
    #   결과: verify 의 restatement 검사(gid in field_map_groups)가 조용히 건너뛴다
    #   = 본 라운드 최대 restatement 원천이 WARN_RESTATEMENT 를 못 받는다 (발견 #3).
    "name": "fq073_export_exposure",
    "provenance": {
        "store_build_hash": META["store_build_hash"],
        "generator_code_path": META["generator_code_path"],
        "generated_at": META["generated_at"],
    },
    "production_parity_verified": False,
    "embedded_data_through": META["date_max"],   # 패널이 담은 최종 데이터월 말일
}
VERIFY_LEAF_SECTOR = {"leaf": "FIELD", "group_id": "A1_RAWDATA_OHLCVS_daily",
                      "field": "Sector", "series_class": "market_daily"}


def to_verify(node, parity_override=None):
    if node is L:
        d = json.loads(json.dumps(VERIFY_LEAF_STORED))
        if parity_override is not None:
            d["production_parity_verified"] = parity_override
        return d
    if node is SEC:
        return dict(VERIFY_LEAF_SECTOR)
    _, name, args, params = node
    out = {"op": name, "children": [to_verify(a, parity_override) for a in args]}
    for k, v in params.items():
        if k == "_unit":
            out["unit"] = v          # TS_LAG 단위: 월간 저장패널 "m" / 일간 rawdata "d"
        else:
            out[k] = v
    return out


def main():
    compiled = {k: to_compile(v) for k, v in FACTORS.items()}
    for fid, ast in compiled.items():
        with open(os.path.join(OUT, f"ast_{fid}.json"), "w", encoding="utf-8") as f:
            json.dump(ast, f, ensure_ascii=False, indent=1)

    # verify 입력 패키지 — 정직판(parity=False) + 반사실판(parity=True, PIT 판정 격리용)
    for tag, override in (("honest", None), ("counterfactual_parity_true", True)):
        pkg = {
            "strategy_id": "WT_D20260802_001_FQ073_export_surprise",
            "pit": {"sig_date": "2026-07-31", "decision_ts": "2026-07-31"},
            "ast": to_verify(FACTORS["F1_export_surprise"], override),
        }
        with open(os.path.join(OUT, f"ast_verify_input_{tag}.json"), "w", encoding="utf-8") as f:
            json.dump(pkg, f, ensure_ascii=False, indent=1)
    # 대조군 3종도 verify 입력 생성 (정직판)
    for fid in ("F2_export_yoy_level", "F3_export_accel", "F4_export_surprise_secneutral"):
        pkg = {"strategy_id": f"WT_D20260802_001_FQ073_{fid}",
               "pit": {"sig_date": "2026-07-31", "decision_ts": "2026-07-31"},
               "ast": to_verify(FACTORS[fid])}
        with open(os.path.join(OUT, f"ast_verify_input_{fid}.json"), "w", encoding="utf-8") as f:
            json.dump(pkg, f, ensure_ascii=False, indent=1)

    print("[ast] compile 방언 %d개 · verify 입력 %d개 생성"
          % (len(compiled), 2 + 3))
    for fid in compiled:
        print("   -", fid)


if __name__ == "__main__":
    main()
