# 05_emit_lcode_r20.R — R20/FQ-033 index-level Benford forensic filter (alpha_research, diagnostic, characterization)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a

res <- emit_lcode(
  mode="alpha_research", strategy_id="WT-D20260713_004", grade="F",
  metric_type="estimated", selection_type="single", record_type="process",
  construction_type="quality", oos_months=72,
  core_reference="R20/FQ-033 지수-레벨 포렌식(Benford) 필터 검증(도훈 설계 2026-07-13). Benford 점수=R18 코드 재계산(유니버스-agnostic, DART API 0). prereg.sha256 6b7e18a6 / alpha_validation.json / primary 2010-01..2015-12 72m",
  mechanism_hypothesis="Benford FSD 최악 10분위(분식 지문 高) 종목을 4개 지수(K200/KQ150/KOSPI전체/KOSDAQ전체) 구성에서 제거 시 지수 대비 꼬리위험(MDD·하방편차·CVaR·worst5) 개선 여부. 예측: 효과가 감사품질 구배(K200~0→KOSDAQ전체 최대)로 단조 증가하면 필터 정보실재 강증거",
  falsification_attempts="유니버스 4종 × {base(시총가중), ex-flagged(p90 제거·재정규화), 무작위 대조 3seed(동수 제거)} 지수 재구성 + cap-w(권위)·EW(진단) 병기. 꼬리지표 6종(연수익·연변동성·MDD·하방편차·worst5·CVaR20) PerformanceAnalytics 표준. block-bootstrap(block12,nsim2000) 차이 CI. 구배 Spearman. 커버리지 게이트(추정대체 금지): post-2016 소형지수 <25% 정직 제외→primary 2010-2015 확정. survivorship C6 방향 명시.",
  lesson_text=paste0(
    "지수-레벨 Benford 포렌식 필터 = config-scoped negative, survivors 0. 도훈 설계(지수 기질로 전략-필터 교란 원천 제거)로도 R18 null 구제 안 됨. ",
    "★핵심 반증(구배): 예측=감사품질 역순 단조증가(K200~0→KOSDAQ전체 최대). 실측 cap-w MDD개선(random-exfl) K200 +0.021 / KQ150 -0.006 / KOSPI전체 +0.010 / KOSDAQ전체 -0.004 → Spearman(order,effect)=-0.40(예측 +1)·비단조. 예측 최강이어야 할 KOSDAQ전체가 최약(음). ",
    "★모든 지수·모든 꼬리지표 exfl-vs-random CI 0 교차(구별불가). 지수별 꼬리정합 1-2/4=동전. K200 단일 양수(MDD +0.021)=시총집중 단일-drawdown-경로 아티팩트: EW서 +0.002로 소멸·2/4 비정합·CI[-0.045,+0.017]. ",
    "★커버리지 발견: Benford(연차·≥15 원화항목) 커버리지 2009-2015 전 지수 98-100%(QuantiWise) but 2016+ DART전환서 붕괴(KOSDAQ전체 20-25%·KOSPI전체 40%)→소형주 재무항목 결손. primary 2010-2015 확정(availability-driven, prereg 동결). ",
    "power 한계(정직): clean 구간이 2008 GFC(데이터前)·2020 COVID(커버리지 붕괴後) 제외→절대 꼬리검출력 제한. 단 구배 shape 예측은 크래시-표본 무관하게 명확 falsified. survivorship C6: 8.5% 상폐소형주 거래소라벨 결손→긍정주장에 보수적(bias against). ",
    "R18(long-alpha placebo p=0.16 null)을 risk-exclusion overlay framing으로 일반화·확증. 재료 소진 아님(INV-7). next_probe: ①상장폐지·불성실공시 event 예측(rawdata UnfaithfulDisc/AdminStock/TradingHalt AUC·hazard, 구성타당·고민감) ②커버리지 복구 KOSDAQ전체 재검(분기 FSD·항목문턱 완화, screen-tier/RAMP) ③2008/2020 복구 시 crisis 꼬리. KOSPI전체·KOSDAQ전체=배포 봉투 밖 진단-only."),
  tags=c("non_return","accounting_forensic","benford_fsd","index_level","exclusion_overlay","tail_risk","audit_quality_gradient","gradient_falsified","characterization","diagnostic","survivors_0","null_confirm_r18","fq033","r20")
)
cat("[emit] l_code =", if(is.character(res)) res else (res$l_code %||% "emitted"), "\n")
