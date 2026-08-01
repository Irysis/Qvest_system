#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_ast_specs_r2.py — WT-D20260802_001 R2 / FQ-073 next_probe P1+P2

R1 대비 변경:
  ① **단일 방언**. 2026-08-02 ast_verify.py 수리(ALB-001/006/007)로 검증기가 컴파일러
     방언(args / type:leaf+class / params / contract)을 전량 수용한다. R1 이 두 방언을
     동시 생성해야 했던 이유(번역기 부재)가 해소됐으므로 compile 방언 하나만 만든다
     — 두 벌 유지가 곧 어긋남의 원천이었다.
  ② materiality 리프 추가 (P1). MUL 로 서프라이즈에 곱해 경제적 노출 크기로 재척도.
  ③ SUE(변동성 표준화) 변형 추가. R1 진단(rank-IC≈0 인데 top-25 는 음수 = 효과가 꼬리
     에만 있고 그 꼬리가 고변동 니치 HS4 버킷)의 직접 대조.
  ④ TS_MEAN 평활 (P2). R1 회전율 1288%/yr 은 제약 1100% 초과 = 부호 무관 배포 불가.

사전등록 성격: 아래 6 변형은 **귀속(attribution) 설계**로 사전 선언한다 — materiality
  on/off x 변동성표준화 on/off 의 2x2 + 평활 사다리 2단. argmax 로 최종안을 고르는
  sweep 이 아니라, R1 실패의 기전 성분을 분해하기 위한 대조군 배치다
  (selection_type="chain", measurement-graduation par.3 chain 자격요건 1/2/3 준수).
  PRIMARY = G1 (cap-tier 판별용). 배포 후보 = G4/G5 (회전율 제약 충족분).
"""
import json, os

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts/WT_D20260802_001")
PANEL_EXP = "stage_artifacts/WT_D20260802_001/fq073_export_exposure_chapter.parquet"
PANEL_MAT = "stage_artifacts/WT_D20260802_001/fq073_export_materiality.parquet"

META_E = json.load(open(os.path.join(OUT, "fq073_export_exposure_chapter_meta.json"), encoding="utf-8"))
META_M = json.load(open(os.path.join(OUT, "fq073_export_materiality_meta.json"), encoding="utf-8"))

# ── 리프 (dialect-neutral 토큰) ──────────────────────────────────────────────
L = ("leaf_export",)        # firm-month 수출노출 USD  (R1 과 동일 패널·동일 해시)
MT = ("leaf_mat_raw",)      # materiality 원값 M (수출 의존도 추정, 상한 미부과)
MC = ("leaf_mat_cred",)     # materiality credibility 보정판 min(R, 1/R) 가중합


def op(name, args, **params):
    return ("op", name, args, params)


# 성장 / 서프라이즈 (R1 정의 그대로 — 비교 가능성 보존)
G = op("SUB", [op("LOG", [L]), op("LOG", [op("TS_LAG", [L], k=12)])])
S = op("SUB", [G, op("TS_MEAN", [G], window=12)])

# SUE — 자기 변동성으로 표준화한 서프라이즈.
#   기전: 10% 성장 서프라이즈는 안정 버킷에서 강한 정보, 고변동 니치 버킷에서 잡음이다.
#   R1 은 이 구분을 하지 않아 top-25 가 고변동 버킷을 구조적으로 선택했다.
SUE = op("DIV", [S, op("TS_STD", [S], window=12)], eps=1e-8)

# materiality — 수출의존도는 정의상 <=1 이므로 경제적 상한 부과 (CLIP).
MCLIP = op("CLIP", [MT], lo=0.0, hi=1.0)

FACTORS = {
    # ★PRIMARY (P1) — materiality x 서프라이즈. 이 라운드의 핵심 질문(cap-tier 이동) 담당
    "R2_G1_mat_surprise":
        op("CS_ZSCORE", [op("CS_WINSORIZE", [op("MUL", [S, MCLIP])], p=0.02)]),
    # 대조군 A — credibility 보정 materiality (R_h>1 = 매핑이 흐름을 설명 못함 → 감쇠)
    "R2_G1c_matcred_surprise":
        op("CS_ZSCORE", [op("CS_WINSORIZE", [op("MUL", [S, MC])], p=0.02)]),
    # 대조군 B — 변동성 표준화만 (materiality 없이). R1 꼬리-효과 진단의 직접 대조
    "R2_G2_sue":
        op("CS_ZSCORE", [op("CS_WINSORIZE", [SUE], p=0.02)]),
    # 결합 — materiality x SUE
    "R2_G3_mat_sue":
        op("CS_ZSCORE", [op("CS_WINSORIZE", [op("MUL", [SUE, MCLIP])], p=0.02)]),
    # ★P2 — 평활 3M (회전율 1100%/yr 제약 충족 시도)
    "R2_G4_mat_sue_sm3":
        op("CS_ZSCORE", [op("CS_WINSORIZE",
                            [op("TS_MEAN", [op("MUL", [SUE, MCLIP])], window=3)], p=0.02)]),
    # ★P2 사다리 2단 — 평활 6M
    "R2_G5_mat_sue_sm6":
        op("CS_ZSCORE", [op("CS_WINSORIZE",
                            [op("TS_MEAN", [op("MUL", [SUE, MCLIP])], window=6)], p=0.02)]),
}

PRIMARY = "R2_G1_mat_surprise"


def stored_leaf(field, path, meta, value_col):
    return {
        "type": "leaf", "class": "STORED_SCORE", "source": "stored_panel",
        "field": field,
        # ast_verify 는 group_id 미등재 STORED_SCORE 를 보수적으로 restatement 표시한다
        # (ALB-003). 관세 통계는 실제로 매월 전 이력을 개정하므로 이 표시가 옳다 —
        # WARN_RESTATEMENT 는 통과 + 스펙 플래그이며 은폐하지 않는다.
        "embedded_data_through": meta["date_max"],
        "contract": {
            "path": path,
            "value_col": value_col,
            "store_build_hash": meta["store_build_hash"],
            "generator_code_path": meta["generator_code_path"],
            "generated_at": meta["generated_at"],
            # 정직 선언 — 신규 리서치 패널이라 production 대응 코드 경로가 없다.
            # ALB-002 수리 후 false 는 '통과 + parity_unverified 플래그'로 전달된다.
            "production_parity_verified": False,
            "avail_offset_days": None,   # 패널 내 avail_ts 컬럼이 권위
        },
    }


LEAVES = {
    L: lambda: stored_leaf("export_exposure_usd", PANEL_EXP, META_E, "value"),
    MT: lambda: stored_leaf("export_materiality", PANEL_MAT, META_M, "value"),
    MC: lambda: stored_leaf("export_materiality_cred", PANEL_MAT, META_M, "value_cred"),
}


def to_compile(node):
    if isinstance(node, tuple) and len(node) == 1:
        return LEAVES[node]()
    _, name, args, params = node
    out = {"type": "op", "op": name, "args": [to_compile(a) for a in args]}
    p = {k: v for k, v in params.items() if not k.startswith("_")}
    if p:
        out["params"] = p
    if name == "TS_LAG":
        # 노드 최상위 key — ast_compile 은 params 만 엄격검사(미선언 param 거부)하고 그 밖의
        # 노드 key 는 무시한다. ast_verify 는 최상위 unit 을 읽는다. 저장 패널은 월간 행이므로
        # k=12 는 12개월이다 — unit 을 안 적으면 검증기가 12'일' 로 읽어 PIT 추론이 헐거워진다.
        out["unit"] = "m"
    return out


def main():
    compiled = {k: to_compile(v) for k, v in FACTORS.items()}
    for fid, ast in compiled.items():
        with open(os.path.join(OUT, "ast_%s.json" % fid), "w", encoding="utf-8") as f:
            json.dump(ast, f, ensure_ascii=False, indent=1)
        # verify 입력 = 같은 트리 (단일 방언). 두 벌 유지 폐지.
        pkg = {"strategy_id": "WT_D20260802_001_R2_FQ073_%s" % fid,
               "pit": {"sig_date": "2026-07-31", "decision_ts": "2026-07-31"},
               "ast": ast}
        with open(os.path.join(OUT, "ast_verify_input_%s.json" % fid), "w", encoding="utf-8") as f:
            json.dump(pkg, f, ensure_ascii=False, indent=1)
    print("[ast-r2] %d 팩터 스펙 + verify 입력 생성 (단일 방언)" % len(compiled))
    for fid in compiled:
        print("   -", fid, "(PRIMARY)" if fid == PRIMARY else "")


if __name__ == "__main__":
    main()
