# -*- coding: utf-8 -*-
"""P2R05 사양 16개 생성기(결정론 · 등록 전 1회 · 기록용으로 남긴다) — DESIGN_draft.md §4 · §12 구현 계약 + 조정자 지시(10-18 · 판단 T2 C-20261018-038 수용 · 칸 12 → 14 ·
   판단 T1 R-20261018-007 수용 · 칸 14 → 16).

만드는 것(specs/ · 이 파일 밖은 읽기만):
  기준 RX0 2      = P2R04_E{2,3}_RX0.json 사본 — code · label 만 바꾼다
  재시드 RX0S 2   = 같은 구성 RX0 사양에서 base_signal.path 만 재시드 엔진(engine_RX0S.R — 원본과 .SEED_BASE 한 줄만 다름 · 경로 = 매니페스트)으로 · 진단 형식
  변형 V1 · V2 4  = 같은 구성 RX0 사양에서 base_signal.path 만 분위 엔진 파일(DT_2002_06975/engine_V{1,2}.R)로 · 이름 · 서술 · 시행 회계
  진단 6(E2)      = Q50 · N1 · N2 · S1 · S2 = E2 RX0 사양에서 base_signal.path 만 engine_<규칙>.R · W2 = engine_blend [engine.R · engine_V2.R]
  비교 기준 LV 2  = P2R04_E{2,3}_W2.json 사본(저변동 D03_RealVol 12.5% 스크린) — code · label 만 바꾼다
시행 회계: 변형만 가산 — 계보(family_root)마다 앞선 모든 사전등록 칸 n_family 최댓값(이 라운드 사전등록은 뺀다 · register.R nf_prior 와 같은 규칙) + 변형 칸 수.
  진단 칸 = RX0 회계(remeasure_of · n_trials_note 제외) + diagnostic_of · control · design_ref · n_trials_note. RX0 · LV = 원본 회계 그대로(무가산 · 사전등록 n_family = NA).
검사(정본) = register.R P2R05_CONST$spec_checks(precheck.R --dry 가 같은 함수를 부른다) — 이 생성기는 검사기가 아니다.
엔진 파일은 다른 구현 에이전트 소관이다 — 여기서는 경로 문자열만 쓴다(존재 · md5 는 engine_checks.R 이 본다).
실행: python make_specs.py   (표준 라이브러리만 · 같은 입력이면 같은 바이트)
"""
import copy
import glob
import io
import json
import os
import sys

ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
ROUND = "P2R05_distribution_target"
RD = os.path.join(ROOT, "04_Research/programs/P2_DEFENSE", ROUND)
P4_SPECS = os.path.join(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/specs")
DT_ENGINE = ROOT + "/04_Research/strategies/DT_2002_06975/engine_%s.R"
CODE_VERSION = "DT_2002_06975/dnn_quantile/rev1"   # DESIGN §7.2 · §12 판본 식별자(서술에만 싣는다)
ENGINES = ["E2", "E3"]
VARIANTS = ["V1", "V2"]
N_ROUND = len(VARIANTS) * len(ENGINES)            # 시행 수 가산 칸 = 변형 칸(규칙 2 × 구성 2)

ENG_TXT = {
    "E2": dict(base="EW(동일 비중 · 25종) · 팩터 없음",
               keep="셀 엔진 · 비중법(EW 25) · 고정 축은 E2 RX0 그대로 — DNN 몫 100% 에 처치가 든다"),
    "E3": dict(base="lean:entropy(엔진 자체 엔트로피 비중 · 순위 버퍼 2배 · B6_36 정의) · 기존 팩터 3(M01 · V10 · M08) · base_weight 0.5",
               keep="비중 lean:entropy · 순위 버퍼 2배 · 기존 팩터 3(M01_Mom_12_1 · V10_FCF_Yield · M08_Residual_Mom) · base_weight 0.5 는 E3 RX0 그대로 — DNN 몫 50% 에 처치가 든다(DESIGN §2.3)"),
}
ENGINE_FACT = ("2002.06975 DNN5(RP_AUTO_2002_06975/engine.R 3판)와 같은 31 특징 · 같은 순위 재척도 5일 표적 · 같은 1,000일 창 · 같은 5영업일 갱신 일정 · 같은 시드에서 "
               "출력층만 50 → 3(τ = 0.1 · 0.5 · 0.9) · 손실 MSE → 합성 pinball(Koenker & Bassett 1978 · Zou & Yuan 2008) · 예측 뒤 행별 재배열"
               "(Chernozhukov, Fernández-Val & Galichon 2010)로 바꾼 분위 DNN(CODE_VERSION %s · DESIGN §3.1 · §3.3)" % CODE_VERSION)
VAR_TXT = {
    "V1": dict(name="꼬리 거부",
               rule="q̂10 이 그날 엔진 적격 집합 하위 20%(순위/N ≤ 0.2 · 동률 평균 · 논문 5분위 단위 — Abe & Nakagawa 2020)면 NA(후보 제외) · 나머지 = q̂50 순위",
               form="제약형 — 꼬리 제약 아래 중심 최대화(Bassett, Koenker & Kordas 2004 비관 배분의 쌍대형)"),
    "V2": dict(name="꼬리 순위",
               rule="점수 = q̂10(예측 VaR(10%) 최소화 = 비관 점수 λ = 1 · 모수 없음)",
               form="목적형 — Choquet 비관 효용의 꼬리 분위(Bassett, Koenker & Kordas 2004) · 좌꼬리 위험이 낮은 종목의 이후 수익(Atilgan, Bali, Demirtas & Gunaydin 2020)"),
}
# 진단 칸(E2 · 판정 표 밖 · 시행 수 무가산) — tag 는 register.R spec_checks 가 label 에서 찾는다
DIAG = {
    "Q50": dict(control="center_only", pair=["V1", "V2"], tag="중앙값만(꼬리 미사용)",
                design_ref="DESIGN §4 · §5.1(중심 효과) · §0b 열린 질문 9",
                what="같은 분위 DNN 의 q̂50 을 점수로 — 추정 대상 '평균 → 중앙값'만의 효과 · V1 − Q50 = 거부의 효과"),
    "N1": dict(control="tail_perm", pair=["V1"], tag="무정보 꼬리 순열 짝(V1)",
               design_ref="DESIGN §4 · §5.1(희석) · §0b 1",
               what=("하방 폭 s = q̂50 − q̂10 을 신호일 안에서 무작위 순열(주 시드 = 엔진 상수 .DT_PERM_SEED · 월 하위 시드 = 엔진 시작 달 대비 순번 · "
                     "rf_cell_engine null_perm 규약 승계)하고 q̃10 = q̂50 − s_perm 으로 V1 규칙 — 같은 비율 무작위 제외(희석 · 선정 교란)의 몫")),
    "N2": dict(control="tail_perm", pair=["V2"], tag="무정보 꼬리 순열 짝(V2)",
               design_ref="DESIGN §4 · §5.1(희석) · §0b 1",
               what="점수 = q̂50 − s_perm(V2 규칙 · 중심은 두고 꼬리 정보만 지운 V2)"),
    "S1": dict(control="vol_proxy", pair=["V1"], tag="변동성 순위 대응 짝(V1)",
               design_ref="DESIGN §4 · §5.1(변동성 누출 · 꼬리 고유) · §0b 2",
               what=("그날 s 값들을 직전 실현 변동성 순위대로 다시 배정(σ 큰 종목에 큰 s · 창 = 엔진 상수 .DT_SIGMA_WIN · 최소 관측 .DT_SIGMA_MIN · 창 끝 t−1 · 수정 종가 · "
                     "σ 결측 = 그날 s 중앙값)하고 q̃10 = q̂50 − s_σ 로 V1 규칙 — 꼬리 정보가 변동성 누출인가(같은 주변분포 · 순서만 σ — measurement-graduation §2 축별 누출 귀무 형식)")),
    "S2": dict(control="vol_proxy", pair=["V2"], tag="변동성 순위 대응 짝(V2)",
               design_ref="DESIGN §4 · §5.1(변동성 누출 · 꼬리 고유) · §0b 2",
               what="점수 = q̂50 − s_σ(V2 규칙)"),
    "W2": dict(control="capacity_pair", pair=["V2"], pair_e3=True, tag="용량 짝(V2 · 50%)",
               design_ref="DESIGN §2.3 · §4 · §5.1(용량) · 판단 T1 C-20261018-027 교훈 승계",
               what=("engine_blend [RP_AUTO_2002_06975/engine.R(평균 표적) · DT_2002_06975/engine_V2.R] = 신호일 횡단면 rank-Z 평균(0.5 × rank-Z(평균) + "
                     "0.5 × rank-Z(q̂10) · rf_cell_engine engine_blend) — E3 의 처치 몫 50% 를 E2 에서 재현해 '용량 의존'과 '구성 의존'을 가른다")),
}
LV_TAG = "비교 기준 LV"
# 재시드 짝(판단 T1 R-20261018-007 · C-054 · 055 · 056 수용 · 조정자 10-18 · 칸 14 → 16) — RX0 엔진과 .SEED_BASE 한 줄만 다른 사본(구현 에이전트 A 생성 · 경로 = 매니페스트)
RSD_TAG = "재시드 짝"
RX0S_DEFAULT = "04_Research/strategies/DT_2002_06975/rx0s/engine_RX0S.R"
MANIFEST = os.path.join(ROOT, "04_Research/strategies/DT_2002_06975/engines_manifest.json")
RSD_REF = "DESIGN §0b 결정 2 개정(시드 짝 — 이 라운드 안에서 잰다) · 판단 T1 R-20261018-007(C-20261018-054 · 055 · 056)"


def rx0s_rel():
    """engine_checks.R P2R05_DTC$rx0s_rel 과 같은 규칙 — 매니페스트 안 engine_RX0S.R 로 끝나는 path 문자열(하나) · 없으면 기본값."""
    try:
        man = load(MANIFEST)
    except Exception:
        return RX0S_DEFAULT
    hit = set()

    def walk(node):
        vals = node.values() if isinstance(node, dict) else (node if isinstance(node, list) else [])
        for v in vals:
            if isinstance(v, str) and (v == "engine_RX0S.R" or v.endswith("/engine_RX0S.R")):
                hit.add(v.replace("\\", "/")[2:] if v.startswith("./") else v.replace("\\", "/"))
            if isinstance(v, (dict, list)):
                walk(v)
    walk(man)
    return hit.pop() if len(hit) == 1 else RX0S_DEFAULT


def load(p):
    with io.open(p, encoding="utf-8") as f:
        return json.load(f)


def dump(obj, p):
    with io.open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def lineage(sa):
    v = sa.get("lineage")
    return list(v) if isinstance(v, list) else ([v] if v else [])


def nf_prior(fam):
    """register.R P2R05_CONST$nf_prior 와 같은 규칙 — 계보 fam 의 앞선 사전등록 칸 n_family 최댓값(이 라운드 제외 · 숫자 · 사양 경로 있는 칸만)."""
    best = 0
    for p in glob.glob(os.path.join(ROOT, "stage_artifacts/programs/*/*/prereg.json")):
        if os.path.basename(os.path.dirname(p)) == ROUND:
            continue
        try:
            d = load(p)
        except Exception:
            continue
        for z in d.get("cells", []) or []:
            n = z.get("n_family")
            if not isinstance(n, (int, float)) or isinstance(n, bool) or not z.get("path"):
                continue
            try:
                s = load(os.path.join(ROOT, z["path"]))
            except Exception:
                continue
            if (s.get("selection_accounting") or {}).get("family_root") == fam:
                best = max(best, int(n))
    return best


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # 콘솔 코드페이지(cp949)에서 '—' · '·' 출력이 죽지 않게(파일 쓰기와 무관)
    except Exception:
        pass
    os.makedirs(os.path.join(RD, "specs"), exist_ok=True)
    out = {}
    for e in ENGINES:
        rx = load(os.path.join(P4_SPECS, "P2R04_%s_RX0.json" % e))
        lv = load(os.path.join(P4_SPECS, "P2R04_%s_W2.json" % e))
        fam = rx["selection_accounting"]["family_root"]
        n0 = nf_prior(fam)
        # 기준 RX0 — code · label 만
        s = copy.deepcopy(rx)
        s["code"] = "P2R05_%s_RX0" % e
        s["label"] = rx["label"].replace("P2R04 같은 배치 — P2R03_%s_RX0 사양 복사" % e, "P2R05 같은 배치 — P2R04_%s_RX0 사양 복사" % e)
        if s["label"] == rx["label"]:
            sys.exit("[make_specs] %s RX0 label 치환 실패(원본 문구가 바뀌었다) — 손으로 맞추지 않는다" % e)
        out[s["code"]] = s
        # 재시드 짝 RX0S — RX0 사양에서 base_signal.path 만 재시드 엔진으로 · 이름 · 서술 · 진단 회계
        rs = rx0s_rel()
        s = copy.deepcopy(rx)
        s["code"] = "P2R05_%s_RX0S" % e
        s["base_signal"]["path"] = ROOT + "/" + rs
        s["label"] = ("%s × 진단 RX0S — %s(평균 표적 DNN · 시드만 다름 — .SEED_BASE 한 줄 · 기저 = %s) · P2R05_%s_RX0 짝 진단(시드 잡음 띠)"
                      % (e, RSD_TAG, rs.replace("04_Research/strategies/", ""), e))
        s["idea"] = ("[P2R05 진단 · %s × RX0S] %s — RX0 엔진(RP_AUTO_2002_06975/engine.R 3판)과 .SEED_BASE 한 줄만 다른 사본(%s · 구현 에이전트 A 생성 · 템플릿 차분 검사기가 "
                     "'시드 한 줄'을 단정) · 같은 31 특징 · 같은 표적 · 같은 1,000일 창 · 같은 일정 · 다른 시드 → RX0 대비 위기 포착 차의 시드 잡음 띠를 잰다(판정 아님 · 읽기 · 결론 범위 8). "
                     "%s · 판정 표 밖 · 시행 수 무가산(%s)" % (e, RSD_TAG, os.path.basename(rs), ENG_TXT[e]["keep"].replace("처치가 든다", "재시드가 든다"), RSD_REF))
        sa = {k: v for k, v in rx["selection_accounting"].items() if k not in ("remeasure_of", "n_trials_note")}
        sa["diagnostic_of"] = "P2R05_%s_RX0" % e
        sa["control"] = "seed_pair"
        sa["design_ref"] = RSD_REF
        sa["n_trials_note"] = "%s(RX0 · 시드만 다름) — 진단 칸 · 시행 수 무가산 · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재" % RSD_TAG
        s["selection_accounting"] = sa
        out[s["code"]] = s
        # 변형 V1 · V2 — base_signal.path · 이름 · 서술 · 회계만
        for v in VARIANTS:
            t = VAR_TXT[v]
            s = copy.deepcopy(rx)
            s["code"] = "P2R05_%s_%s" % (e, v)
            s["label"] = "%s × 분포 표적 %s %s(%s · 기저 = DT_2002_06975/engine_%s.R)" % (e, v, t["name"], t["rule"], v)
            s["base_signal"]["path"] = DT_ENGINE % v
            s["idea"] = ("[P2R05 분포 표적 · %s × %s] 기저 = %s · engine_%s.R. 점수 = %s — %s. %s · 완전 투자 · 시점 신호 없음(DESIGN §3.4)"
                         % (e, v, ENGINE_FACT, v, t["rule"], t["form"], ENG_TXT[e]["keep"]))
            s["selection_accounting"] = {
                "selection_type": "sweep", "family_root": fam,
                "lineage": ["RX_" + ROUND] + lineage(rx["selection_accounting"]),
                "n_family_at_registration": n0 + N_ROUND,
                "n_trials_basis": ("P2R05: 앞선 사전등록 칸 중 계보 %s(E2 · E3 공통) 회계 최댓값 %d + 이 라운드 변형 칸 %d(소비 규칙 2 × 구성 2) · "
                                   "RX0 · 진단 · 비교 기준 칸 무가산" % (fam, n0, N_ROUND)),
            }
            out[s["code"]] = s
        # 진단(E2 만)
        if e == "E2":
            sa0 = {k: v for k, v in rx["selection_accounting"].items() if k not in ("remeasure_of", "n_trials_note")}
            for g, d in DIAG.items():
                s = copy.deepcopy(rx)
                s["code"] = "P2R05_E2_%s" % g
                pairs = ["P2R05_E2_%s" % p for p in d["pair"]] + (["P2R05_E3_%s" % p for p in d["pair"]] if d.get("pair_e3") else [])
                if g == "W2":
                    s["base_signal"] = {"kind": "engine_blend", "paths": [rx["base_signal"]["path"], DT_ENGINE % "V2"]}
                    src_txt = "engine_blend [RP_AUTO_2002_06975/engine.R · DT_2002_06975/engine_V2.R]"
                else:
                    s["base_signal"]["path"] = DT_ENGINE % g
                    src_txt = "기저 = DT_2002_06975/engine_%s.R" % g
                s["label"] = "E2 × 진단 %s — %s(%s) · %s 짝 진단" % (g, d["tag"], src_txt, " · ".join(pairs))
                s["idea"] = ("[P2R05 진단 · E2 × %s] %s — %s. %s · 분위 DNN = %s · 판정 표 밖 · 시행 수 무가산(%s)"
                             % (g, d["tag"], d["what"], src_txt, ENGINE_FACT, d["design_ref"]))
                sa = dict(sa0)
                sa["diagnostic_of"] = pairs[0] if len(pairs) == 1 else pairs
                sa["control"] = d["control"]
                sa["design_ref"] = d["design_ref"]
                sa["n_trials_note"] = "%s — 진단 칸 · 시행 수 무가산 · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재" % d["tag"]
                s["selection_accounting"] = sa
                out[s["code"]] = s
        # 비교 기준 LV — P2R04 W2 사본(code · label 만 · 판단 T2 C-20261018-038)
        s = copy.deepcopy(lv)
        s["code"] = "P2R05_%s_LV" % e
        s["label"] = ("%s × %s — 저변동 스크린(D03_RealVol · base_weight %s · P2R04_%s_W2 사양 사본 · 판단 Superfan T2 C-20261018-038 · 진단 형식 · 시행 수 무가산)"
                      % (e, LV_TAG, json.dumps(lv["base_weight"]), e))
        out[s["code"]] = s
    for code, s in out.items():
        dump(s, os.path.join(RD, "specs", code + ".json"))
    print("[make_specs] %d개 — %s" % (len(out), " · ".join(out.keys())))


if __name__ == "__main__":
    main()
