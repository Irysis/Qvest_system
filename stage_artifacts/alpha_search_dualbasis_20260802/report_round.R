#==============================================================================
# report_round.R — 2026-08-02 alpha-search 밤샘 라운드 수집
#   dual-basis JSON 4건 읽기 → sweep 차트 → 라운드 L-code 적립 → close_round →
#   텔레그램 발송(tg_agent_brief 단일 진입점, charts 첨부 의무)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
INFRA <- file.path(ROOT, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "telegram", "telegram_notify.R"))
source(file.path(INFRA, "telegram", "tg_chart_pack.R"))
source(file.path(INFRA, "axiom", "lcode_emit.R"))
source(file.path(INFRA, "contracts", "close_round.R"))

OUT <- file.path(ROOT, "stage_artifacts", "alpha_search_dualbasis_20260802")
labs <- c("spec_mass_lowfreq_60d_BASE", "spec_mass_lowvol",
          "resid_info_vol_BASE", "resid_info_vol_M60")
short <- c("추세-저주파(원논문)", "추세x저변동성(신규)",
           "잔차거래량(원논문)", "잔차거래량-60일평활(신규)")

rd <- lapply(labs, function(l) {
  p <- file.path(OUT, sprintf("dualbasis_%s.json", l))
  if (!file.exists(p)) return(NULL)
  fromJSON(p, simplifyVector = TRUE)
})
names(rd) <- labs
ok <- !vapply(rd, is.null, logical(1))
cat("[report] dual-basis 산출 존재:", paste(labs[ok], collapse = ", "), "\n")
stopifnot(any(ok))

g <- function(l, f, d = NA_real_) { x <- rd[[l]]; if (is.null(x)) return(d); as.numeric(x[[f]] %||% d) }
gew <- function(l, f, d = NA_real_) { x <- rd[[l]]$diag_ew_universe; if (is.null(x)) return(d); as.numeric(x[[f]] %||% d) }
gct <- function(l, f, t) { x <- rd[[l]]$diag_cap_tier; if (is.null(x) || !isTRUE(x$available)) return(NA_real_); as.numeric(x[[f]][[t]] %||% NA_real_) }

tab <- data.table(
  label     = labs[ok], short = short[ok],
  capw_t    = vapply(labs[ok], g,   numeric(1), "portfolio_alpha_t_nw_lag3"),
  net_sr    = vapply(labs[ok], g,   numeric(1), "net_sr"),
  ir        = vapply(labs[ok], g,   numeric(1), "information_ratio"),
  ew_t      = vapply(labs[ok], gew, numeric(1), "portfolio_alpha_t_nw_lag3"),
  ew_oos    = vapply(labs[ok], gew, numeric(1), "oos_retention_approx"),
  ew_p17t   = vapply(labs[ok], gew, numeric(1), "post2017_t_nw_lag3"),
  w_mega    = vapply(labs[ok], gct, numeric(1), "weight_share_avg", "MEGA"),
  w_mid     = vapply(labs[ok], gct, numeric(1), "weight_share_avg", "MID"),
  w_other   = vapply(labs[ok], gct, numeric(1), "weight_share_avg", "OTHER")
)
print(tab)
fwrite(tab, file.path(OUT, "round_summary_20260802.csv"))

# ── sweep 차트 (cap-w 권위 PORT_t vs HARD 2.95) ───────────────────────────────
ch1 <- tg_chart_sweep(labels = tab$short, values = round(tab$capw_t, 3),
                      out_dir = OUT, title = "canonical PORT_t (cap-w 권위) vs 자본 문턱 2.95",
                      value_label = "다중검정 t값 (NW lag-3)", hline = 2.95,
                      hline_label = "자본 투입 문턱 2.95",
                      filename = "sweep_capw_port_t_20260802.png")
ch2 <- tg_chart_sweep(labels = tab$short, values = round(tab$ew_t, 3),
                      out_dir = OUT, title = "EW-유니버스 대비 PORT_t (dual-basis 진단)",
                      value_label = "다중검정 t값 (EW 벤치)", hline = 2.95,
                      hline_label = "자본 투입 문턱 2.95",
                      filename = "sweep_ew_port_t_20260802.png")
charts <- c(ch1, ch2)
cat("[report] charts:", paste(charts, collapse = " | "), "\n")

# ── 라운드 L-code (canonical_screen 실측 근거) ───────────────────────────────
best <- tab[which.max(capw_t)]
lc <- emit_lcode(
  mode = "alpha_search",
  strategy_id = "AS_ROUND_20260802_DUALBASIS",
  grade = "F",
  metric_type = "canonical_screen",
  construction_type = "single_factor_long_only",
  selection_type = "chain",
  family = "technical_price",
  core_reference = paste(
    "2026-08-02 alpha-search 라운드: 07-27 QUARANTINE 2건(Sepp-Lucic 2026 저주파 스펙트럼 질량 /",
    "Bucci et al. 2026 SMAR 잔차 거래량)의 documented next_probe 소비 + 4-arm canonical dual-basis 재측정."),
  lesson_text = sprintf(paste(
    "07-27 QUARANTINE 2건은 proxy(hurdle_gate)에서만 기각되고 canonical/dual-basis 미측정 상태였다.",
    "본 라운드가 4-arm 전부 canonical_screen_bt 실측으로 재측정 — cap-w PORT_t 최대 %.3f (%s),",
    "EW-유니버스 대비 최대 %.3f, 4arm 전부 자본 문턱 2.95 미달. cap-tier 분해상 보유의 %.0f%%가",
    "OTHER(시총 31위+) tier라 mega-cap 벤치 아티팩트로 설명되지 않는다 — 즉 이번 기각은",
    "벤치 구성이 아니라 신호 자체에 귀속된다."),
    max(tab$capw_t, na.rm = TRUE), best$short[1], max(tab$ew_t, na.rm = TRUE),
    100 * mean(tab$w_other, na.rm = TRUE)),
  mechanism_hypothesis = paste(
    "★핵심(전이층 실측): 잔차거래량 60거래일 평활은 rank-IC를 전혀 바꾸지 못했는데",
    "(0.00236→0.00214, t 0.42→0.33 — 둘 다 0과 구분 불가) canonical cap-w PORT_t는",
    "0.219→1.048로 4.8배 올랐다(회전율 1026%→662%, CAGR 8.33%→11.97%). 즉 회전율 평활은",
    "횡단 신호력이 아니라 IC→PORT_t 전이 효율에 작용하는 독립 레버이며, 시스템 1순위 병목인",
    "전이 벽에 실측 가능한 손잡이가 존재함을 보인다. 단 전이 레버는 신호력에 곱해지는 배수이지",
    "대체재가 아니다 — rank-IC가 0이므로 4.8배를 해도 1.05로 문턱 2.95에 미달한다.",
    "② 추세-저주파: 저변동성 하위 3분위로 좁히자 MDD는 61.4%→57.5%로 3.9%p만 줄고",
    "IC는 0.0138→0.0081(t 2.39→1.24), FF3 알파 +4.28%/yr→-0.87%/yr, cap-w PORT_t",
    "0.756→-0.958로 반전. 즉 이 전략의 낙폭은 고변동성 종목 선택이 아니라 벤치마크",
    "동조(BM상관 0.74 유지)에서 오고 추세 지속성 알파는 오히려 고변동 구간에 실재한다",
    "— 저변동성 조건부는 MDD 레버로 반증되고 남은 레버는 오버레이 계열뿐."),
  falsification_attempts = list(
    list(test = "canonical_screen_bt 실측 재측정(4arm, cap-w 권위 basis)",
         result = "falsified", effect_retained = 0,
         detail = sprintf("cap-w PORT_t 최대 %.3f << 2.95 HARD", max(tab$capw_t, na.rm = TRUE))),
    list(test = "dual-basis EW-유니버스 대비(v8.3 기각 전 의무)",
         result = "falsified", effect_retained = 0,
         detail = sprintf("EW-uni PORT_t 최대 %.3f — cap-w 대비 상향이나 문턱 미달", max(tab$ew_t, na.rm = TRUE))),
    list(test = "cap-tier(MEGA/MID/OTHER) 분해 — mega-cap 벤치 아티팩트 가설",
         result = "falsified", effect_retained = 0,
         detail = sprintf("보유 비중 OTHER %.0f%% / MEGA %.1f%% — 벤치 아티팩트로 설명 불가",
                          100 * mean(tab$w_other, na.rm = TRUE), 100 * mean(tab$w_mega, na.rm = TRUE))),
    list(test = "저변동성 조건부(MDD 레버 가설) A/B",
         result = "falsified", effect_retained = 0,
         detail = "MDD 61.4%→57.5%(-3.9%p)뿐, FF3 알파 +4.28%/yr→-0.87%/yr 반전"),
    list(test = "60거래일 평활(회전율 트랩 가설) A/B — 신호축",
         result = "falsified", effect_retained = 0,
         detail = "회전율 1026%→662%에도 rank-IC 무변화(0.00236→0.00214) — 횡단 신호 부재는 불변"),
    list(test = "60거래일 평활 — 전이축(IC→PORT_t) 부수 실측",
         result = "survived", effect_retained = 1,
         detail = "canonical cap-w PORT_t 0.219→1.048(4.8x) — 전이 효율 레버는 실재하나 문턱 미달")
  ),
  portfolio_alpha_t = max(tab$capw_t, na.rm = TRUE),
  oos_retention = max(tab$ew_oos, na.rm = TRUE),
  oos_months = 258L,
  tags = c("ALPHA_SEARCH", "DUAL_BASIS", "VALIDATED_HARD_FAIL", "CHAIN_ITERATION"),
  metrics = list(
    n_months = 258L,
    capw_port_t_max = max(tab$capw_t, na.rm = TRUE),
    ew_port_t_max   = max(tab$ew_t, na.rm = TRUE),
    post2017_t_max  = max(tab$ew_p17t, na.rm = TRUE),
    weight_share_other_avg = mean(tab$w_other, na.rm = TRUE),
    bench_provenance = paste(
      "본 라운드 벤치 무결성 확인(2026-08-02 RAWDATA BM_Ret 2026-07 오염 경보 대응):",
      "canonical 4arm의 bench_dt는 build_monthly_forward_returns가 K200∪KQ150 유니버스",
      "Close/Size로 현장 구성한 시총가중 forward return(factor_validation.R:48-53)이며,",
      "본 하네스의 RAWME 컬럼 선택에 BM_Ret이 포함되지 않는다. run_alpha_search 경로의",
      "BM_DT도 BM_CACHE=.cache/benchmark.parquet(config.R:61, backtest_harness.R:173)에서",
      "온다. 실측 확인: 마지막 신호월 2026-06-30의 벤치 -22.76%로 정본 -23.63%와 정합하며",
      "오염값 -17.70%가 아니다 → 본 라운드 수치는 오염 비영향."),
    next_probe = paste(
      "P1 추세-저주파 OVERLAY_CANDIDATE 라우팅(신호는 고변동 구간 실재·낙폭은 벤치동조 귀속 →",
      "국면/DD overlay가 남은 유일 레버, overlay_pit_guard HARD + lag1 스트레스 의무);",
      "P2 추세-저주파 알파의 pre/post-2017 구조 절단 규명(EW-uni post2017_t≈0.07 — 감쇠 함수형 진단 FQ-055 재적용)")
  ),
  project_root = ROOT
)
cat("[report] L-code emit 반환:", paste(utils::head(as.character(unlist(lc)), 3), collapse = " | "), "\n")

# ── close_round (계약 강제: next_probe>=2 · 소비면 · negative면 부활조건) ────
cr <- close_round(
  round_id = "AS-20260802-R1",
  verdict_type = "config_scoped_negative",
  layer = "signal",
  mechanism_diagnosis = paste(
    "4-arm canonical 실측에서 cap-w PORT_t 최대", sprintf("%.3f", max(tab$capw_t, na.rm = TRUE)),
    "— 자본 문턱 2.95 미달. 두 chain 프로브가 각각의 기전 가설을 분리 판정했다:",
    "잔차거래량은 rank-IC가 평활 전후 불변(0.0024→0.0021)이라 횡단 신호 자체가 0이나,",
    "같은 신호에서 cap-w PORT_t는 0.219→1.048(4.8x)로 올라 회전율 평활이 IC→PORT_t",
    "전이 효율에 작용하는 독립 레버임이 드러났다(전이 벽 = 시스템 1순위 병목).",
    "추세-저주파는 낙폭이 변동성 노출이 아니라 벤치 동조에서 오며 알파는 고변동 구간에 국소",
    "— 저변동성 조건부는 PORT_t 0.756→-0.958로 역효과. cap-tier 분해상 보유 86~96%가",
    "OTHER(시총 31위+) tier라 mega-cap 벤치 아티팩트 설명은 배제된다."),
  next_probes = c(
    "P1 ★전이층 레버 격리 측정 — 회전율 평활(smoothing window)을 이미 PORT_t가 양(+)인 기존 챔피언 신호(PG2 score_eff 구성요소)에 이식해 4.8x 배수가 신호력 있는 곳에서도 재현되는지 A/B. 본 라운드는 rank-IC=0 위에서 관측돼 배수 자체의 상한을 못 봄. FQ-059(soft-membership/cost-optimized top-N) 인접 축",
    "P2 추세-저주파(spec_mass) OVERLAY_CANDIDATE 라우팅 — 국면/DD overlay를 MDD 레버로 A/B (overlay_pit_guard HARD + lag1 스트레스 + strict-PIT A/B 의무)",
    "P3 추세-저주파 알파의 2017 전후 구조 절단 규명 — EW-uni post2017 t 0.068 대 전기간 1.405, FQ-055 감쇠 함수형 진단(계단 단절 vs smooth) 재적용",
    "P4 잔차거래량 selection 축은 신호-null 실측이므로 monitoring 축(비정상 거래량 지속 = 이벤트 tripwire)으로 재과녁"
  ),
  consumer_surfaces = c(
    "선별 라벨: 4arm 전부 자본 tier 미달 — screen-tier 라우팅 판정 재료로 등재",
    "구성/비중 계층: 회전율 평활 = 전이 효율 레버 실측(0.219→1.048) — 챔피언 신호 이식 대상(P1)",
    "오버레이/국면 입력: spec_mass 신호를 OVERLAY_CANDIDATE 큐로 라우팅(P2)",
    "monitoring 신호: 잔차거래량 지속 수준을 tripwire 후보로 이관(P4)"
  ),
  frontier_update = "FQ 신규 등재 대상 — ①회전율-평활 전이 레버의 챔피언 이식 ②spec_mass x overlay(MDD 레버) 미측정 면",
  live_trigger = paste(
    "부활 조건: ① overlay 적용 A/B에서 MDD 45% 미만 + cap-w PORT_t 2.0 초과 동시 달성 시",
    "spec_mass 라인 재개 ② 2017 이후 추세 지속성 스프레드(저주파 질량 상하위 격차) 재확대 발화 시",
    "③ 비-return 원천(거래량 이외 정보 도달 프록시) 등재 시 잔차거래량 기전 재검"),
  evidence_refs = c(
    "stage_artifacts/alpha_search_dualbasis_20260802/round_summary_20260802.csv",
    "stage_artifacts/alpha_search/20260802_021210_1868 (RESID_INFO_VOL_M60)",
    "stage_artifacts/alpha_search/20260802_021901_32432 (SPEC_MASS_LOWVOL)"
  )
)
cat(paste(as.character(unlist(if (is.list(cr)) (cr$summary %||% cr) else cr)), collapse = "\n"), "\n")

# ── 텔레그램 (tg_agent_brief 단일 진입점 + charts 의무) ──────────────────────
fmt <- function(x) if (is.finite(x)) sprintf("%.2f", x) else "NA"
kv <- list(
  "다중검정t 최고(시총가중 벤치)" = sprintf("%s (%s) / 문턱 2.95", fmt(max(tab$capw_t, na.rm = TRUE)), best$short[1]),
  "다중검정t 최고(동일가중 벤치)" = sprintf("%s — 이중기준 진단값", fmt(max(tab$ew_t, na.rm = TRUE))),
  "2017년 이후 다중검정t"         = sprintf("%s (동일가중 기준)", fmt(max(tab$ew_p17t, na.rm = TRUE))),
  "보유 시총구간 구성"            = sprintf("31위밖 %.0f%% / 상위10 %.0f%%",
                                  100 * mean(tab$w_other, na.rm = TRUE), 100 * mean(tab$w_mega, na.rm = TRUE)),
  "측정 라벨"                     = "실측 canonical_screen (258개월)"
)
tg_agent_brief(
  agent = "AlphaSearch",
  title = "논문 2편 후속 검증 4건 — 자본 문턱 미달, 기전은 분리 규명",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "논문 2편의 후속 아이디어 4가지를 21년치로 재검증 — 실제 자본은 넣지 않습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 지난주 탈락한 논문 2편의 '이렇게 고치면 될까' 안 4가지를 검증",
           "방법: 2005년~현재 258개월 모의 운용 + 기준을 두 가지로 바꿔 교차 확인",
           "결과: 4가지 모두 우연이 아닐 확신도(2.95)에 크게 못 미침",
           "의미: 자본 배정은 없고, 한 아이디어만 보조장치 재료로 남깁니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치", kv = kv),
    list(type = "bullet", emoji = "🔬", heading = "기전 규명(이번 라운드 소득)",
         items = c(
           "★거래 회전율만 낮췄더니 정보계수는 그대로인데 실현 t값이 4.8배",
           "즉 '신호를 포트폴리오로 옮기는 효율'에 별도 손잡이가 실재한다는 실측",
           "다만 그 손잡이는 배수라서 신호가 0이면 4.8배도 0에 가깝다",
           "추세 지속성: 저변동성으로 좁히니 낙폭은 3.9%p만 줄고 알파는 음수로 반전",
           "보유의 86~96%가 시총 31위 밖 — 초대형주 벤치 아티팩트로 설명 불가")),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "표본외 유지율 음수 — 개발 기간 밖에서 성과가 유지되지 않음",
           "추세 신호의 2017년 이후 t값 0.07로 사실상 소멸",
           "전이 효율 4.8배는 신호가 0인 구간에서 관측 — 상한은 미측정")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "회전율 평활을 이미 유효한 기존 챔피언 신호에 이식해 배수 재현성 확인",
           "추세 신호는 국면/낙폭 오버레이 후보로 라우팅해 별도 검증",
           "2017년 전후 구조 절단의 함수형 진단 재적용",
           "잔차 거래량은 종목선택 축을 접고 감시 신호 축으로만 재과녁"))
  ),
  charts = charts
)
cat("[report] telegram 발송 완료\n")
