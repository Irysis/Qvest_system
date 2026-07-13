# 04_emit_lcode.R — R18/FQ-031 회계-포렌식 통계 팩터 2종 (alpha_research, canonical_screen, sweep)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a

res <- emit_lcode(
  mode="alpha_research", strategy_id="WT-D20260713_002", grade="F",
  metric_type="canonical_screen", selection_type="sweep", record_type="performance",
  portfolio_alpha_t=0.568, oos_months=191,
  core_reference="R18/FQ-031 회계-포렌식 통계 팩터 2종(재무제표 통계기법, DART API 0·cached fundamental_merged.parquet). prereg.sha256 f5b797b2 / alpha_validation.json / 2009-06..2025-06 191m frozen panel",
  mechanism_hypothesis="① F-A 수정Jones(Dechow1995) 재량적 발생액 잔차 = 이익조정 프록시(high=short) ② F-B Benford FSD(Amiram2015) 재무제표 첫자리 분포 MAD 이탈도 = 조작 지문(high=short)",
  falsification_attempts="2종 canonical dual-basis(top25 EW 15bps liq2e8 cap-w authoritative) full/IS(<2019)/OOS(>=2019) + 월간 rank-IC + placebo corp-shuffle 200draw + Size-partial 잔차 재스크리닝 + EW-uni·cap-tier 병기 + F-A vs AC13ref(원본 Jones) 증분성 corr + F-B vs Size corr. prereg hash 대조. IS-only 선택. Step0 필드가용성 게이트(추정대체 금지) 통과.",
  lesson_text=paste0(
    "회계-포렌식 통계 2종(재무제표 통계기법) = 2/2 config-scoped negative, survivors 0. ",
    "F-A 수정Jones 재량발생액: cap-w PORT_t 0.449·IS1.07→OOS-0.57·EW-uni -0.33·EW post2017 -1.05. ★핵심 증분성 KILL: F-A vs 기존 AC13(원본 Jones, DB등재) 횡단 corr **0.991** → KR 대형주서 ΔREC 수정항 무증분(수정Jones≈원본Jones). AC13은 이미 standalone LO top25 FAIL(2026-06-06 PORT_t 0.227 Grade F). = 신규 아님·중복 확증. ",
    "F-B Benford FSD(virgin family, 시스템 첫 측정): cap-w PORT_t 0.568·IS0.79→OOS-0.14·EW-uni -0.30·**placebo p=0.160**(신호구조 없음)·rank-IC t=-1.00(가설 부호 반대·무의미). ★Size 위장 아님 확증(FB_vs_Size corr 0.006·Size-partial 0.45 불변) — 그러나 clean null. 해석: KR 대형주(K200∪KQ150)=최고감사 세그먼트→조작 분산 낮음 + FSD ~33항목 노이즈. ",
    "★dual-basis 판결: 둘 다 EW-universe basis에서도 음(-0.33/-0.30) → cap-w mega-cap 벤치 아티팩트 아님(FQ-008 재분류군 해당無)·진짜 알파 부재. cap-tier OTHER 90-95%(소형집중)나 EW조차 음=tier무관 부재. ",
    "종합: 재료(통계기법×재무제표)는 소진 아님(INV-7). frontier next_probe: F-B worst-decile EXCLUSION overlay·소형universe(RAMP)·quarterly FSD·F-A×F-B composite forensic screen. add_factor 없음. K-IFRS2011+소스전환2016 구조단절은 monthly-z로 완화. n_trials=2 sweep, DSR moot(best 0.57≪hurdle)."),
  tags=c("non_return","accounting_forensic","discretionary_accruals","modified_jones","benford_fsd","earnings_quality","sweep","canonical_screen","survivors_0","redundant_ac13","null_vs_placebo","fq031","r18")
)
cat("[emit] l_code =", res$l_code %||% res$lcode %||% "?", "\n")
