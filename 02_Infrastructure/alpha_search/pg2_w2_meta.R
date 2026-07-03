# pg2_w2_meta.R — 최종 meta JSON (chain 규약 + n_trials + 판정) + placebo 진단
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(ROOT, "stage_artifacts/pg2_w2_earnings3m")
d <- fread(file.path(OUTDIR, "measure_results.csv"))
pair <- fread(file.path(OUTDIR, "paired_vs_baseline.csv"))
build_meta <- fromJSON(file.path(OUTDIR, "build_meta.json"))

get1 <- function(sig, var, col) d[signal == sig & variant == var, get(col)][1]

meta <- list(
  date = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  task = "PG2 강화 로드맵 P1 — earnings@3M lead 정제(논문근거 신호 3종 + 보유밴드) 실측",
  roadmap = "04_Research/pg2_reinforcement_roadmap_20260702.md P1",
  mode = "alpha_search",
  selection_type = "chain",
  n_trials = 8L,   # 8 신호/composite (BASE + S1/S2/S3 + COMP_S1/S2/S3/ALL). band=구현규칙(별도 신호 아님).
  n_trials_note = "chain(가설주도 순차개선): 각 composite = 논문 메커니즘 1개의 컨센서스-레벨 충실 사상. IS-only. holdout 미접촉. DSR는 sweep 아님 → 진단산출만.",
  honesty_labels = list(
    broker_level = "브로커(개인 애널리스트)-레벨 데이터 없음 → 3 신호 전부 컨센서스-레벨 충실 사상(consensus-level faithful mapping)으로 명시.",
    recommendation_proxy = "S3 3-신호 합의의 '투자의견(recommendation)' 축 = 원 시트 미보유 → ESBR(% 상향 breadth)을 추천계열 대리로 사용(명시 라벨).",
    metric_type = "canonical_screen (contract build_benchmark_compare, NW lag-3). admission-binding 아님(forge build_bt_result가 authoritative)."
  ),
  change_reason_log = list(
    "iter1 BASE_earn3m = 내부 Round7/8 earnings family(C01/C02/C04/C05/C06/C19 z-평균) 재현 → contract-grade 기준선 확립.",
    "iter2 S1_innovrev(Gleason-Lee 혁신 리비전 분리) = herding 리비전 제거 목적: EPS리비전 시리얼 streak + trailing dispersion 대비 innovation z.",
    "iter3 S2_tpsect(Da-Schaumburg TP 섹터상대) = raw TP_gap의 베타-노이즈 제거 목적: Z_Sector(WICS 섹터중립).",
    "iter4 S3_consensus(3-신호 합의) = 상충신호 제거 목적: EPS/ESBR/TP 동방향 합의 count×강도.",
    "iter5 COMP_* = 각 신호를 baseline과 결합(S2는 TP_gap 슬롯 치환) — 증분 확인.",
    "iter6 보유밴드(Blitz 2023) = 회전 억제 목적: top-25 진입 + 상위 45% 잔류 시 보유. 전 composite A/B."
  ),
  pit = build_meta$pit_notes,
  ic_diagnostics_1m = build_meta$ic_diagnostics_1m_forward,
  gates = list(
    graduation_HARD = "PORT_t(NW)>=2.95 AND oos_retention>=0.7 AND calmar>=0.64 (forge-authoritative). 본 측정은 canonical_screen → graduation 선언 금지.",
    screening = "SR>=0.7 & CAGR>=12% 또는 score>=40&SR>=0.5"
  ),
  key_results = list(
    baseline = list(signal = "BASE_earn3m", PORT_t = get1("BASE_earn3m","plain_full","PORT_t_NW"),
                    absSR = get1("BASE_earn3m","plain_full","absSR"),
                    calmar = get1("BASE_earn3m","plain_full","calmar"),
                    turnover = get1("BASE_earn3m","plain_full","turnover"),
                    note = "내부 H3 earnings family. IC강(t_full 6.59)이나 long-only PORT_t 약 = IC≠PORT_t 재확인(메모리 정합)."),
    best = list(signal = "S3_consensus + 보유밴드", variant = "band_full",
                PORT_t = get1("S3_consensus","band_full","PORT_t_NW"),
                absSR = get1("S3_consensus","band_full","absSR"),
                calmar = get1("S3_consensus","band_full","calmar"),
                turnover = get1("S3_consensus","band_full","turnover"),
                paired_NW_t_vs_baseline = pair[signal=="S3_consensus" & variant=="band", paired_NW_t][1],
                verdict = "graduation 후보(forge 재측정 필요). PORT_t 2.20 < HARD 2.95 & calmar 0.587 < 0.64 → 자본 graduation 미달. 단 baseline 대비 paired-NW-t +2.03로 유의 개선 = 의미있는 결과."),
    band_effect = "보유밴드는 회전율을 3~10배 절감(예 S3 13.06→3.59). 지속성 신호(S3/S1)는 PORT_t 상승, 노이즈 신호(BASE/S2)는 하락 — 밴드는 signal persistence를 요구.",
    recent_2021 = "전 신호 recent(2021+) PORT_t <0.12(대부분 음) = cohort-wide decay-pattern 재확인(메모리 earnings decay 2015+ 정합). full-period/pre-2015 edge.",
    lag1_stress = "lag1 추가지연 시 PORT_t 대폭 하락(S3 1.505→0.472) = earnings-revision 신호의 빠른 시간 감쇠(정상). 동월 누출 아님(신호는 이미 ym말·forward ym+1로 PIT-clean).",
    s2_fail = "S2_tpsect(섹터상대 TP) = PORT_t 음(−0.12 full, −1.30 recent). Da-Schaumburg 섹터중립이 KR long-only에 비이전. VALIDATED negative.",
    qtr_diag = "분기 리밸(3M-horizon native 진단) PORT_t < 월간 = 메모리 WS3(분기 self-synth 착시) 정합. 월간 contract가 authoritative."
  ),
  artifacts = list(
    panel = "stage_artifacts/pg2_w2_earnings3m/panel_signals.parquet",
    results = "stage_artifacts/pg2_w2_earnings3m/measure_results.csv",
    paired = "stage_artifacts/pg2_w2_earnings3m/paired_vs_baseline.csv",
    charts = c("equity_curve.png", "annual_returns.png"),
    build_meta = "build_meta.json"
  )
)
write_json(meta, file.path(OUTDIR, "meta_pg2_w2.json"), auto_unbox = TRUE, pretty = TRUE, digits = 5)
cat("[meta] meta_pg2_w2.json written\n")
cat(sprintf("BEST S3+band: PORT_t %.2f absSR %.2f calmar %.2f TO %.1f paired-t %.2f\n",
    get1("S3_consensus","band_full","PORT_t_NW"), get1("S3_consensus","band_full","absSR"),
    get1("S3_consensus","band_full","calmar"), get1("S3_consensus","band_full","turnover"),
    pair[signal=="S3_consensus" & variant=="band", paired_NW_t][1]))
