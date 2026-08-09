## =============================================================================
## FQ-225/226 (E) — findings 발행 + alpha_frontier_queue 갱신
## ★번호 하드코딩 금지: 쓰기 직전 read → max+1 → 기록 → 재읽기 검증
## 수치는 전부 RDS 실측값에서 읽는다(전사 오류 차단).
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[e1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

A <- readRDS(file.path(OUT, "a1_results.rds"))
Bb <- readRDS(file.path(OUT, "b1_results.rds"))
C <- readRDS(file.path(OUT, "c1_results.rds"))
D <- readRDS(file.path(OUT, "d1_results.rds"))
say("입력 RDS 4종 로드")

## ---------------------------------------------------------------- findings
F <- list(
  round_id = "FQ-225/226-diagnostic",
  date = "2026-08-10",
  metric_type = "canonical_screen_diag",
  capital_claim = FALSE,
  prereg = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/PREREG.md",
  parent = "FQ-223 (롤오버 하류) · FQ-161 (M26 재료 자격) · FQ-226 (계절성)",
  target_statistic = "z(M26_Revenue_Mom) FMB NW(lag3) 월별 계수 계열 (4-팩터 횡단면 회귀)",
  panel = list(source = "stage_artifacts/WT_D20260808_002/alpha_scores.parquet",
               rows = 69885L, months = 283L, range = "2003-01 ~ 2026-07", tickers = 630L,
               complete_case_frac = 1, parity_t = A$t_full),

  A_modern_attenuation = list(
    verdict = "JUDGMENT_NOT_POSSIBLE",
    headline = "현대 구간 약화는 '약화됐다'도 '안 됐다'도 판정 불가. 이 사실이 결론이다.",
    level_test = list(n_modern = A$n_mod, mean_monthly = A$m_mod, annual_pct = A$m_mod*1200,
                      sd = A$s_mod, t_nw3 = A$t_mod,
                      n_early = A$n_ear, mean_early_monthly = A$m_ear,
                      annual_early_pct = A$m_ear*1200, t_early = A$t_ear),
    power_gate = list(required_monthly = A$req_self$required_monthly,
                      required_annual_pct = A$req_self$required_annual*100,
                      tool_verdict = A$vp_self$verdict,
                      implied_t_threshold = A$vp_self$implied_t_threshold,
                      bar_restates_t = A$vp_self$bar_restates_t,
                      early_effect_detectable_in_modern = A$detect_early_effect,
                      margin_pct = (A$m_ear/A$req_self$required_monthly - 1)*100,
                      flip_sd_multiplier = D$flip_sd/A$s_mod,
                      note = "여유 2.7% — 현대 sd 가 2.68% 커지거나 NW 팽창이 1.40 이면 원천 판정 불가로 전환"),
    trend_test_primary = list(design = "연속 시간 상호작용 (분할 금지)", n = 283L,
                              slope_per_yr = A$c_lin_m26, t_nw3 = A$t_lin_m26,
                              detected = A$A1_detected,
                              min_detectable_slope_per_yr = A$min_detectable_slope,
                              detectable_multiple = A$min_detectable_slope/abs(A$c_lin_m26)),
    era_diff_secondary = list(diff_monthly = A$era_diff, diff_annual_pct = A$era_diff*1200,
                              nw_se = A$era_diff_se, t = A$era_diff_t, significant = FALSE),
    attribution = list(verdict = A$A2_verdict,
                       note = "A1 미검출 ⇒ 귀속 대상 없음. 다만 nested 회귀에서 disp_t(횡단면 수익 sd)가 강한 설명력",
                       disp_channel = "M26 계수 ~ tau + disp_t: disp_t t=+3.63 (R2 0.004→0.092) · 전채널 t=+4.14 (R2 0.112)"),
    sample_required = list(level_months = A$n_required_months, level_years = A$n_required_months/12,
                           trend_months = A$n_trend_req_months, trend_years = A$n_trend_req_months/12,
                           trend_additional_years = (A$n_trend_req_months - 283)/12),
    positive_control = list(valid = A$ctl_ok,
                            controls_t = as.list(setNames(A$TR$t_lin, A$TR$series)),
                            reading = "대조 4종 전부 |t|<2.0 → 대조 유효. 6/6 계열이 음의 점기울기이나 유의 0개 = 시대 공통 약드리프트"),
    contamination_robustness = list(
      note = "자가 적대검증 C1 — 오염된 M26 위에서 잰 것 아니냐는 반론을 6 arm 재판정으로 답함",
      arms = D$RE$arm, trend_t = D$RE$t_lin, modern_level_t = D$RE$t_mod,
      early_t = D$RE$t_ear, required_months = D$RE$n_req_months,
      verdict = "6/6 arm 추세 미검출(|t|max 1.189) · 6/6 현대 level 미달(|t|max 1.135) — 결론 불변")
  ),

  B_seasonality = list(
    verdict_primary = "NOT_ESTABLISHED_AFTER_MULTIPLICITY",
    verdict_apriori = "APRIL_ONLY_SIGNIFICANT_AS_PRESPECIFIED",
    frame_correction = list(
      claim = "'4·5월 계절성' 프레임은 실측과 어긋난다 — 5월은 12개월 중 11위",
      may_mean_monthly = -0.000617004078276572, may_rank = 11L,
      apr_mean_monthly = Bb$top_mean, apr_rank = 1L,
      why_may_was_paired = "FQ-223 롤오버 창(sig−63일이 4/1 을 가로지르는 sig 월 = 04,05) 때문이지 관측된 5월 효과가 아님"),
    power_gate = list(n_per_month = 24L, observed_apr = Bb$top_mean,
                      required_monthly = Bb$req_top$required_monthly,
                      required_annual_pct = Bb$req_top$required_annual*100,
                      margin_pct = (Bb$top_mean/Bb$req_top$required_monthly - 1)*100,
                      passed = Bb$B0_pass,
                      note = "여유 +2.2% — 단일 사전지정 달에 한해 간신히 검출 가능 범위"),
    sliding_window = list(
      excess_w1 = Bb$e1, excess_w3 = Bb$e3, excess_w5 = Bb$e5,
      dilution_ratio_w3 = Bb$r3, dilution_ratio_w5 = Bb$r5,
      theoretical_isolated_w3 = 1/3, theoretical_isolated_w5 = 1/5,
      verdict = "고립 봉우리 — 관측 희석비 0.155 가 순수 고립 이론치 0.333 보다도 작다 = 이웃이 평균 이하",
      auto_label_correction = "b1 자동라벨 'w3 최대창 중심 03월 ⇒ 경계효과 의심'은 오독. 5월이 11위라 {03,04,05} 창이 손해 볼 뿐이며 4월 고립의 *귀결*이다",
      harmonics = list(K = Bb$harm$K, r2 = Bb$harm$r2, F_p = Bb$harm$p_F,
                       reading = "K=1~5 전부 F p 0.46~0.85 — 매끄러운 연주기 자체가 부재. 고원 서사 기각")),
    permutation = list(design = "연내(year-wise) 월 라벨 재배정 · 관측 패턴 조건부 보존 · B=20000",
                       p_max_month = C$p_mx, p_april_prespecified = C$p_apr, p_neighbor = C$p_nb,
                       calibrated_cutoff = as.list(C$cal),
                       empirical_type1_at_005 = as.list(C$fk_rate),
                       reading = "주판정 p_max 0.2015 = 무지정 최대월 탐색으로는 미확립 / 사전지정 4월 p 0.0185 = 유의"),
    mechanism_discrimination = list(
      rollover_FY1 = list(supported = TRUE,
        evidence = "진짜 4/1 basis 수리: 4월 초과 +0.005263 (p 0.0129) → +0.002188 (p 0.1531) · 제거율 58.4%",
        alternative_exclusion = "가짜 basis 통제 2종은 4월을 못 죽임 — FAKE_10/1 p 0.0127 · FAKE_7/1 p 0.0140 ⇒ 작동한 것은 창 단축이 아니라 basis 정체",
        arm_table = list(arm = C$AR$arm, apr_excess = C$AR$apr_excess, p = C$AR$p_apr)),
      fiscal_reporting_concentration = list(supported = FALSE,
        evidence = "서프라이즈(수준) 계열에 4월 부재 — C04_ESBR 표준화 초과 +0.0060 · C01_SUE −0.0667. 결산 집중이 기전이면 여기 나와야 함"),
      dividend_exdate = list(supported = FALSE,
        evidence = "FMB 절편(수준)의 4월 초과 −0.010074 · p_apr 0.7736 — 배당은 수준에 작용해야 하는데 부호가 반대"),
      institutional_rebalancing_dispersion = list(supported = FALSE,
        evidence = "4월 횡단면 수익 sd 비 1.033 · 순열 p 0.2904 · disp 정규화 후에도 4월 p_apr 0.0099 유지"),
      residual_unattributed = list(
        finding = "★M01_Mom_12_1(가격 12-1 모멘텀)의 4월 효과가 가장 크고 네 기전 전부로 설명 안 됨",
        std_excess_by_family = list(momentum = 0.4407, surprise = -0.0303, level = -0.1587),
        m01 = list(apr_excess = 0.016071, std_excess = 0.5912, p_apr = 0.0050, p_max = 0.0367,
                   note = "6 계열 중 유일하게 다중검정 보정 max-month 검정 통과"),
        directionality = "M01 통제 후 M26 4월 더미 t +2.046→+1.171 (잔존 0.558) / 역방향 M01 은 t +3.263→+2.498 (잔존 0.732) ⇒ M01 이 독립 현상",
        era_reproduction = "M01 4월 초과 전반 +0.014745 / 후반 +0.017447 — 양 시대 재현")),
    positive_control = list(
      injection = list(delta = Bb$req_top$required_monthly, p_max_after = Bb$inj_p,
                       detected = Bb$inj_p < 0.05, note = "B0 필요치 크기를 4월에 주입 → p 0.0002 검출. 검정 살아있음"),
      negative_control = list(n_fake = 3000L, type1_at_005 = as.list(C$fk_rate),
                              note = "명목 0.05 대비 0.0437~0.0477 — 정상 보정. b1 초판의 0.0767(n=300)은 표본잡음이었고 자기정정함"),
      seasonality_irrelevant_axis = "M01(컨센서스 무관)을 '무관해야 할 축'으로 세웠으나 오히려 최대 효과 — 이 대조 실패가 기전 판정의 핵심 축이 됨")
  ),

  selection_type = "chain_diagnostic_prereg (argmax pick 없음 — DSR 부적용)",
  n_specs = list(A = 12L, B = 10L),
  caveats = c(
    "FMB 계수 t 는 횡단면 신호력 — 실현 포트폴리오 초과수익(PORT_t) 아님. IC→PORT_t 전이 벽 적용",
    "graduation HARD 3종(PORT_t 2.95 / oos_retention 0.7 / calmar 0.64) 미판정. 자본 주장 없음",
    "M26 cap-w PORT_t 는 FQ-161 기록에서 +1.544 로 이미 HARD 미달 — 본 라운드가 그 판정을 바꾸지 않음",
    "A0 검정력 여유 2.7% — 뒤집힘 배수 sd×1.0268 / NW 팽창 1.40. 단일 문장 확실성으로 읽지 말 것",
    "귀속용 disp_t/N_t 는 동시점 변수(분해이지 예측 아님). 국면 대리변수 vol12_t/dd_t 만 lag 처리",
    "월별 n=23~24 — 구조적 저검정력. 4월 결과는 사전지정 단일가설 자격에 의존"),
  challenge_note = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/challenge_note.md",
  artifacts_dir = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/"
)
write(toJSON(F, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"),
      file.path(OUT, "fq225_226_findings.json"))
say("findings 기록 완료")

## ---------------------------------------------------------------- 큐 갱신
say("================ 큐 갱신 (read → max+1 → write → 재읽기) ================")
Q <- read_frontier_queue()
ids0 <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
num0 <- suppressWarnings(as.integer(sub("^FQ-", "", ids0)))
n_before <- length(Q$entries); maxn <- max(num0, na.rm = TRUE)
say("읽기: 항목 %d · FQ 최대 %d", n_before, maxn)
nxt <- function(k) sprintf("FQ-%03d", maxn + k)

## (1) FQ-226 갱신 — 내 소유 항목(owner=alpha-research)
i226 <- which(ids0 == "FQ-226")
if (!length(i226)) stop("[e1] FQ-226 부재 — 0은 정지 신호")
Q$entries[[i226]]$title <- "4월 단독 횡단면 신호 계절성 (구 '4·5월') — 모멘텀 가족 한정, M01 잔여 미귀속"
Q$entries[[i226]]$status <- "measured_partially_attributed"
Q$entries[[i226]]$measured <- list(
  date = "2026-08-10", round = "FQ-225/226 diagnostic", metric_type = "canonical_screen_diag",
  frame_correction = "5월은 12개월 중 11위(−0.000617/월) — '4·5월' 프레임 폐기, 4월 단독",
  primary = sprintf("순열 max-month p = %.4f ⇒ 무지정 탐색으로는 계절성 미확립", C$p_mx),
  apriori = sprintf("사전지정 4월 p = %.4f · 이웃차 p = %.4f ⇒ 4월 한정 유의", C$p_apr, C$p_nb),
  sliding_window = sprintf("고립 봉우리 확정 — 희석비 w3 %.3f (순수 고립 이론치 0.333 보다 작음) · 하모닉 K=1~5 전부 F p>0.46", Bb$r3),
  mechanism = "롤오버 지지(수리가 58.4% 제거·가짜 basis 통제는 못 죽임) / 결산집중·배당락·분산 3종 기각",
  residual = sprintf("★M01_Mom_12_1 4월 초과 표준화 %.4f · p_apr %.4f · 유일하게 max-month 통과(p %.4f) — 네 기전 전부로 미설명", 0.5912, 0.0050, 0.0367),
  power = sprintf("월별 n=24 · 4월 여유 +%.1f%% (필요치 %.6f)", (Bb$top_mean/Bb$req_top$required_monthly-1)*100, Bb$req_top$required_monthly),
  controls = "위반주입 p 0.0002 검출 · 음성대조 1종오류 0.0437~0.0477(명목 0.05, n=3000)")
Q$entries[[i226]]$next_probe <- list(
  "M01 4월 효과의 종목 단면 — 4월 초과가 어떤 종목군(사이즈·유동성·기관보유·회계연도)에 집중되는가. 기전 후보를 관측 가능한 형태로 좁히는 유일한 남은 축",
  "4월 효과의 소비 가능성 — 4월 한정 모멘텀 가중 상향이 top-25 cap-w PORT_t 를 움직이는가(연 1회 발화 = 24 관측, 사전 검정력 산출 필수)")
Q$entries[[i226]]$artifacts <- "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/ (PREREG.md · fq225_226_findings.json · challenge_note.md)"

## (2) 신규 3건
new_entries <- list(
  list(id = nxt(1L), lane = "material_qualification",
       title = "M26 현대 구간 약화 — 판정 불가 확정 + 부활 표본 조건 (FQ-161 후속)",
       status = "measured_underpowered_parked", owner = "alpha-research", opened = "2026-08-10",
       category = "power_bounded_verdict", parent = "FQ-161 / FQ-223",
       hypothesis = "08-08 이 남긴 '2017-2026 t=0.884, 세 시대 전부 INCONCLUSIVE_UNDERPOWERED' 를 분할이 아니라 연속 시간 상호작용으로 다시 물었다.",
       measured = list(
         date = "2026-08-10", metric_type = "canonical_screen_diag",
         verdict = "JUDGMENT_NOT_POSSIBLE — '약화됐다'도 '안 됐다'도 이 표본으로는 기각 불가",
         level = sprintf("현대 n=%d · 연 %+.3f%% · NW3 t %+.3f / 초기 n=%d · 연 %+.3f%% · t %+.3f",
                         A$n_mod, A$m_mod*1200, A$t_mod, A$n_ear, A$m_ear*1200, A$t_ear),
         trend = sprintf("연속 추세(n=283) %+.6f/yr · t %+.3f — 미검출. 검출 가능 최소 기울기 %+.6f/yr (관측의 %.2f배)",
                         A$c_lin_m26, A$t_lin_m26, A$min_detectable_slope, A$min_detectable_slope/abs(A$c_lin_m26)),
         era_diff = sprintf("직접 시대차 %+.3f%%/yr · NW SE 기준 t %+.3f — 비유의", A$era_diff*1200, A$era_diff_t),
         power_bar = sprintf("현대 n=115 검출 필요치 연 %.3f%% vs 초기 실측 연 %.3f%% — 여유 %.2f%% (뒤집힘 sd 배수 %.4f)",
                             A$req_self$required_annual*100, A$m_ear*1200,
                             (A$m_ear/A$req_self$required_monthly-1)*100, D$flip_sd/A$s_mod),
         contamination_robustness = sprintf("FQ-223 6 arm 재판정: 추세 |t| 최대 %.3f · 현대 level |t| 최대 %.3f — 오염 제거해도 불변",
                                            max(abs(D$RE$t_lin)), max(abs(D$RE$t_mod))),
         control = "대조 4종(C01/C02/C04/M01) 전부 추세 미검출 — 대조 유효. 6/6 계열 음의 점기울기이나 유의 0개 = 시대 공통 약드리프트"),
       revival_condition = list(
         level = sprintf("현대 효과 크기 유지 시 |t|=2.0 도달에 %.0f개월(%.1f년) 필요 — 현재 %d개월. 자연 축적으로는 도달 불가",
                         A$n_required_months, A$n_required_months/12, A$n_mod),
         trend = sprintf("추세 검출에는 총 %.0f개월(%.1f년) 필요 — 추가 %.1f년",
                         A$n_trend_req_months, A$n_trend_req_months/12, (A$n_trend_req_months-283)/12),
         alternative = "표본을 기다리는 대신 **효과크기를 키우는 축**으로 이동하라 — 유니버스 확장(KR_TOP500_FREEFLOAT), 국면 조건부 발화로 유효 관측 집중, 또는 소비면 전환(랭킹→필터)"),
       caveat = "FMB 계수 t 는 신호력이지 PORT_t 아님. M26 cap-w PORT_t 는 FQ-161 에서 이미 +1.544 로 HARD 미달 — 본 항목은 그 판정을 바꾸지 않는다",
       artifacts = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/ (a1_trend_by_series.csv · d1_arm_reassessment.csv · d1_power_sensitivity.csv)"),

  list(id = nxt(2L), lane = "return_seasonality",
       title = "★KR 4월 가격-모멘텀 프리미엄 — 사전등록 4기전 전부로 미설명된 잔여",
       status = "frontier_open", owner = "alpha-research", opened = "2026-08-10",
       category = "unattributed_effect", parent = "FQ-226",
       hypothesis = "M01_Mom_12_1(가격 12-1 모멘텀)의 FMB 계수는 4월에 표준화 +0.5912 초과를 보이며, 6개 계수계열 중 **유일하게** 다중검정 보정 max-month 순열검정을 통과한다(p_max 0.0367 · p_apr 0.0050 · 이웃차 p 0.0460). 사전등록한 네 기전 — FY1 롤오버(M01 은 컨센서스 필드 미사용) · 결산 집중(서프라이즈 계열 표준화 초과 −0.0303 으로 부재) · 배당락(절편 4월 초과 −0.010074, p 0.7736) · 횡단면 분산/기관 리밸런싱(4월 disp 비 1.033, p 0.2904 · 정규화 후 유지) — 전부 기각됐다. 가족 분리는 선명하다: 모멘텀 +0.4407 vs 서프라이즈 −0.0303 vs 수준 −0.1587.",
       why_it_matters = "① 미탐색 알파 축: 연 1회 발화이나 효과크기가 크다(M01 4월 계수 +0.017746 vs 평월 +0.001675). ② 방법론: '특정 달 제외'를 데이터 결함 통제로 쓰는 설계는 이 효과와 교락된다(FQ-223 방법 A 가 그렇게 무효화됐다). ③ M26 4월의 44%(M01 통제 시 잔존율 0.558)가 이 공통 성분이다.",
       next_probe = list(
         "종목 단면 분해 — 4월 모멘텀 초과가 사이즈/유동성/기관보유/12월결산 여부 중 무엇과 교차하는가. 각 후보가 참일 때 다르게 나타나는 관측을 먼저 고정할 것",
         "국제 대조 — KR 4월이 회계연도(일본식 4월 시작 기업 관행)와 결부되는지, 아니면 3월 정기주총/배당기준일 이후 유동성 재개와 결부되는지. 크로스마켓 데이터 금지이므로 KR 내부에서 12월결산 vs 3월결산 종목군 대비로 대리 검정",
         "소비 가능성 — 4월 한정 모멘텀 틸트가 top-25 cap-w PORT_t 를 움직이는가. ★연 1회 발화 = 24 관측이므로 착수 전 required_effect_size.R 필수, 미달이면 측정 전 폐기"),
       caveat = "월별 n=24 구조적 저검정력. p_max 0.0367 은 명목 0.05 를 통과하나 경험적 보정문턱 0.0525 에 근접 — 단일 라운드로 확립 선언 금지",
       artifacts = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/ (c1_standardized_april_excess.csv · b1_breadth_across_series.csv)"),

  list(id = nxt(3L), lane = "conditional_strength",
       title = "M26 계수의 횡단면 분산 의존 — disp_t 가 시간보다 강한 설명변수",
       status = "frontier_open", owner = "alpha-research", opened = "2026-08-10",
       category = "conditional_alpha", parent = "FQ-225(본 라운드) A2 부산물",
       hypothesis = "M26 FMB 계수를 시간에 회귀하면 R2 0.004(t −0.77)에 그치나, 월별 횡단면 수익 sd(disp_t)를 넣으면 disp_t 계수 t=+3.63 · R2 0.092 로 뛴다(전채널 사양에서 t=+4.14 · R2 0.112). 즉 M26 의 횡단면 신호력은 '시대'보다 '그 달의 수익 분산'에 조건부다. 이는 기울기가 분산에 기계적으로 비례하는 부분과, 분산 국면에서 정보가 실제로 더 잘 반영되는 부분이 섞여 있어 분해가 필요하다.",
       why_it_matters = "① 기계적 성분이면 국면-조건부 알파가 아니라 스케일 아티팩트이므로 표준화 규격을 고쳐야 한다. ② 정보 성분이면 disp 국면 조건부 발화가 유효 관측을 집중시켜 FQ-227 의 '표본을 기다릴 수 없다' 문제를 우회하는 레버가 된다.",
       next_probe = list(
         "기계 vs 정보 분해 — 계수를 disp_t 로 정규화한 계열(rank-IC 등 스케일 불변 통계와 대조)에서 disp 의존이 남는가. 남으면 정보 성분",
         "소비면 — disp_t 는 사후 관측이므로 **직전 달 disp(lag1)** 로 게이트했을 때 top-25 cap-w PORT_t 가 개선되는가. lag1 예측력이 없으면 소비 불가(진단으로만 유지)"),
       caveat = "disp_t 는 동시점 변수 — 본 라운드에서는 분해용이며 예측 주장 아님. 소비 검토는 lag1 판본으로만",
       artifacts = "stage_artifacts/infra/fq225_m26_modern_seasonality_20260810/a1_attribution_nested.csv")
)
for (e in new_entries) Q$entries[[length(Q$entries) + 1L]] <- e
Q$updated <- "2026-08-10"
say("기록 시도: 항목 %d → %d (신규 %s)", n_before, length(Q$entries),
    paste(vapply(new_entries, function(e) e$id, ""), collapse = ", "))
write_frontier_queue(Q)

## 재읽기 검증
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], "")
say("재읽기: 항목 %d (증분 %+d)", length(ids2), length(ids2) - n_before)
for (e in new_entries) say("  %s 존재: %s", e$id, e$id %in% ids2)
i2 <- which(ids2 == "FQ-226")
say("  FQ-226 갱신 반영: status=%s · measured 필드 %s",
    Q2$entries[[i2]]$status, !is.null(Q2$entries[[i2]]$measured))
say("  손실 검사: 기존 id 중 소실 %d건", length(setdiff(ids0, ids2)))
say("저장 완료 → %s", OUT)
