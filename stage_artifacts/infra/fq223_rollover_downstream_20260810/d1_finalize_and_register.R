## =============================================================================
## FQ-223 (D) — 판정 확정 + 검정력 수치 회수 + 프론티어 큐 등재
##
## 큐 등재는 `02_Infrastructure/ops/frontier_queue_io.R` 정본 writer 경유.
## ★번호 하드코딩 금지: 쓰기 직전 read → max+1 → write → 재읽기 검증.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
say <- function(fmt, ...) { cat(sprintf(paste0("[d1] ", fmt, "\n"), ...)); flush.console() }

A <- readRDS(file.path(OUT, "a1_results.rds"))
B <- readRDS(file.path(OUT, "b3_results.rds"))
C <- readRDS(file.path(OUT, "c1_results.rds"))

## ------------------------------------------------- [1] 검정력 수치 회수
say("================ [1] 방법 A 검정력 ================")
say("t_full %+.4f (n=%d) → t_A %+.4f (n=%d) · 기대 %+.4f · Δ %+.4f (마진 -0.30)",
    A$t_full, A$n_full, A$t_A, A$n_A, A$t_A_expected, A$t_A - A$t_A_expected)
say("required_effect(n=%d, sd=%.6f): 필요 월평균 %.6f (연 %.3f%%) · 관측 %+.6f (연 %+.3f%%)",
    A$req_A$n, A$req_A$sd_monthly, A$req_A$required_monthly, A$req_A$required_annual*100,
    A$mean_A, A$mean_A*12*100)
say("검정력 라벨: %s", A$vp_A$verdict)
say("  note: %s", A$vp_A$note)
if (!is.null(A$vp_A$implied_t_threshold))
  say("  implied_t_threshold %.3f — 문턱 2.0 근방이면 이 바는 t검정 재진술(WT-001 렌즈1)", A$vp_A$implied_t_threshold)
say("Welch(4·5월 vs 평월) p %.4f · 기여 share %.4f (문턱 0.30) · 월수 share %.4f",
    A$welch_p, A$contrib_share, A$n_AM/A$n_full)

## ------------------------------------------------- [2] 사전등록 규칙 적용
say("================ [2] 사전등록 판정 규칙 적용 ================")
TB <- B$tab
t_plain <- TB[arm=="plain(재구성)", t_nw3]
t_RA    <- TB[arm=="RA_4월탐지", t_nw3]
t_RAraw <- TB[arm=="RA_원탐지기", t_nw3]
t_R0405 <- TB[arm=="RA_04·05국한", t_nw3]
fake_max <- max(abs(c(B$d_oct, B$d_jul)))
rules <- data.table(
  rule = c("철회: t_B < 2.0",
           "재확인: t_A >= 2.0 AND t_B >= 2.0",
           "표본손실 교락: t_A < 2.0 이나 t_A >= 기대-0.30",
           "오염 기여 확정: Welch p < 0.05",
           "오염 비중 물질적: 기여 share >= 0.30",
           "값 분포 물질적: 4월 크기배수 >= 2.0",
           "대조 유효: target_price 4월 배수 ~ 1"),
  value = c(sprintf("t_B(min over RA arms) = %+.4f", min(t_RA, t_RAraw, t_R0405)),
            sprintf("t_A = %+.4f · t_B = %+.4f", A$t_A, t_RA),
            sprintf("t_A - 기대 = %+.4f", A$t_A - A$t_A_expected),
            sprintf("p = %.4f", A$welch_p),
            sprintf("share = %.4f", A$contrib_share),
            sprintf("배수 = %.2f", C$FP[metric=="revenue_fy1" & grp=="04", mag_ratio_vs_other]),
            sprintf("배수 = %.2f (lift %.2f)", C$FP[metric=="target_price" & grp=="04", mag_ratio_vs_other],
                    C$FP[metric=="target_price" & grp=="04", rollover_lift])),
  fired = c(min(t_RA,t_RAraw,t_R0405) < 2.0,
            A$t_A >= 2.0 && t_RA >= 2.0,
            A$t_A < 2.0 && A$t_A >= A$t_A_expected - 0.30,
            A$welch_p < 0.05,
            A$contrib_share >= 0.30,
            C$FP[metric=="revenue_fy1" & grp=="04", mag_ratio_vs_other] >= 2.0,
            abs(C$FP[metric=="target_price" & grp=="04", mag_ratio_vs_other] - 1) < 0.25))
for (i in seq_len(nrow(rules))) with(rules[i], say("  [%s] %-42s %s", if (fired) "발화" else "  · ", rule, value))
VERDICT <- if (min(t_RA,t_RAraw,t_R0405) < 2.0) "RETRACT" else if (A$t_A >= 2.0) "REAFFIRM" else "REAFFIRM_A_UNDERPOWERED"
say("★★사전등록 판정 = %s", VERDICT)

## ------------------------------------------------- [3] findings 산출물
findings <- list(
  round_id = "FQ-223", date = "2026-08-10",
  metric_type = "canonical_screen_diag",
  capital_claim = FALSE,
  prereg = "stage_artifacts/infra/fq223_rollover_downstream_20260810/PREREG.md",
  target_statistic = "z(M26_Revenue_Mom) FMB NW(lag3) t in 4-factor cross-sectional regression",
  threshold = 2.0,
  verdict = VERDICT,
  method_A_exclusion = list(
    t_full = A$t_full, n_full = A$n_full, t_A = A$t_A, n_A = A$n_A,
    t_A_expected_if_no_contamination = A$t_A_expected,
    delta_vs_expected = A$t_A - A$t_A_expected,
    required_monthly = A$req_A$required_monthly, required_annual_pct = A$req_A$required_annual*100,
    power_label = A$vp_A$verdict,
    welch_p_aprmay_vs_other = A$welch_p, contribution_share = A$contrib_share,
    control_M01_failed = TRUE,
    control_M01_note = "M01_Mom_12_1(컨센서스 무관) 도 4·5월 제외 시 t 1.951→0.613 (Welch p 0.0017) — 4·5월은 횡단면 신호 전반에 유리한 달. ⇒ 방법 A 는 달력 계절성과 교락되어 롤오버 증거로 쓸 수 없다"),
  method_B_rollover_aware = list(
    common_window_months = length(B$common_ym),
    t_plain = t_plain, t_RA_aprdet = t_RA, t_RA_rawdet = t_RAraw, t_RA_0405only = t_R0405,
    delta_t_aprdet = B$d_apr, delta_t_rawdet = B$d_raw, delta_t_0405only = B$d_0405,
    fake_control_oct1_delta = B$d_oct, fake_control_jul1_delta = B$d_jul,
    fake_max_abs = fake_max,
    rollover_attribution = "부분적 — 진짜 Δt(+0.650) 가 가짜 최대(+0.398) 를 넘지만 2배 미달. 창-단축 부수효과와 완전 분리 불가",
    verdict_robustness = "6 arm 전부 t >= 2.478 > 문턱 2.0 — 판정은 귀속 논쟁과 무관하게 성립"),
  contamination_scale = list(
    m26_contaminated_frac_judgment_panel = 0.1588,
    m26_apr_frac = 0.8728, m26_may_frac = 0.8873, m26_apr_may_concentration = 0.940,
    m28_contaminated_frac = C$m28_frac, m28_apr_may_concentration = 0.941,
    apr_magnitude_ratio_revenue = C$FP[metric=="revenue_fy1" & grp=="04", mag_ratio_vs_other],
    apr_positive_ratio_revenue = C$FP[metric=="revenue_fy1" & grp=="04", pos_ratio_vs_other],
    matched_control_target_price_ratio = C$FP[metric=="target_price" & grp=="04", mag_ratio_vs_other]),
  downstream = list(
    composites = "M32_Composite_Mom_v2 = mean(z(M01),z(M10),z(M13),z(M24),z(M25)) — M26/M28 미포함 (compute_momentum.R:522-525 실측). M09_Composite_Mom = mean(z(M01),z(M02),z(M05)) — 미포함",
    aliases = "C14_Revenue_Surprise / C17_OP_Revision = M26/M28 과 동일 식(compute_consensus.R:487-506,541-544) 이나 .CONSENSUS_DEPRECATED 로 배출 차단 — emission_ledger n=0 실측",
    pg2_book = "현행 PG2 book 팩터 7종 = C01_SUE/C02_EPS_Chg_1m/C04_ESBR/C06_TP_Gap + Q07_Earnings_Stability/M08_Residual_Mom/Q25_Ohlson_O (05_Production/2.Factor_Model/2-3.../_recompute_alpha_asof.R:13-14). M26/M28/M32 소비 0",
    pg2_instrument_alive = "양성 대조: 같은 grep 이 05_Production 에서 Q07/M08/Q25/V01/Z_Score_Aligned 를 검출 — '0건' 은 계측 사망이 아님",
    research_consumers = "M26 은 RAMP 연구 프로브 3곳이 소비: 02_Infrastructure/ramp/run_ramp_oos_probe_broad.R:11 · run_ramp_oos_probe_fwl.R:8 · ramp/search/build_cache.R:10. M28 은 0곳. 자본 경로 아님",
    production_field_fingerprint = "PG2 소비 벤더필드(sue/eps_chg_1m/esbr) 4월 양비율배수 0.74/1.35/0.71 — 롤오버 지문(≈2.1) 미검출"),
  caveats = c(
    "판정 문턱 2.0 = '재료 자격' 스크린이지 자본 게이트 아님. graduation HARD 3종 미판정",
    "부기간 진단(08-08): 2017-2026 t = 0.884 — 현대 구간 약화가 롤오버보다 큰 실질 위험",
    "DB이식 t_B 는 Δt 가 basis 불변이라는 가정 위의 외삽 — 1급 수치는 arm t 원값",
    "오염 비중은 판정 패널(K200∪KQ150 630종목) scope. 전 유니버스 비중은 미측정"))
write_json(findings, file.path(OUT, "fq223_findings.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
say("findings 기록 → %s", file.path(OUT, "fq223_findings.json"))

## ------------------------------------------------- [4] 프론티어 큐 등재
say("================ [4] 프론티어 큐 등재 ================")
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()                                  # ★쓰기 직전 read
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)]))
nxt <- max(nums, na.rm = TRUE) + 1L
say("현 원장 항목 %d · max FQ 번호 %d ⇒ 신규 시작 %d", length(ids), max(nums, na.rm=TRUE), nxt)

e1 <- list(
  id = sprintf("FQ-%d", nxt),
  title = "M26/M28 FY1 롤오버 수리 — 배출 316개월 중 15.9%/16.2% 가 '개정' 아닌 '기준연도 교체'",
  status = "measured_repair_ready", owner = "dohoon_decision", opened = "2026-08-10",
  category = "infra_factor_definition", parent = "FQ-223 (하류 전파 실측)",
  mechanism = paste0(
    "M26 = (revenue_fy1[최신] - revenue_fy1[<=sig-63L])/|.| · M28 = 동식(op_profit_fy1). ",
    "FY1 기준연도는 매년 4월 첫 영업일에 교체되므로(동시변경 lift revenue 10.82 · op_profit 10.24) ",
    "창이 4/1 을 가로지르는 4·5월 sig 에서 차분은 개정률이 아니라 (FY_{n+1}/FY_n - 1) ≈ 기대성장률이다. ",
    "판정 패널(630종목·283개월) 실측 오염 비중: M26 0.1588 (4월 0.873·5월 0.887·04·05 집중도 0.940) / ",
    "M28 0.1618 (집중도 0.941). 4월 비영 |raw| 크기배수 7.60배 · 양(+)비율 0.740 vs 평월 0.349. ",
    "★PIT 위반 아님(두 끝점 모두 Date<=sig_date) — 결함은 구성 타당도."),
  matched_control = paste0(
    "동일 63일 차분 공식을 target_price(롤오버 lift 0.99)에 가하면 4월 크기배수 0.97 · 양비율배수 1.04 ",
    "⇒ 공식 아티팩트 아님, 롤오버 귀속 성립. 같은 실행·같은 창."),
  impact_measured = paste0(
    "오염은 M26 을 **부풀리지 않고 희석**했다. 외과적 롤오버-인지 수리(같은 279개월) 후 ",
    "z(M26) FMB NW(3) t 2.478 → 3.128 (04·05 국한 수리는 2.810). ⇒ 08-08 재료 자격 판정 재확인. ",
    "단 가짜 basis 통제(7/1)도 Δt +0.398 을 내므로 개선분의 롤오버 귀속은 부분적."),
  scope = paste0(
    "동일 결함 계열 = FY1 레벨을 창으로 차분하는 팩터: M26·M28(배출 중) + C14_Revenue_Surprise·",
    "C17_OP_Revision(동식·배출 차단됨) + SE02 창 확장안(FQ-222). bps_1y(lift 12.83)·dps_1y(18.29)·",
    "eps_1y(11.30) 도 같은 롤오버를 갖지만 현행 소비는 **레벨**(V04/V05/V06)이라 해당 없음. ",
    "V09_PEG 의 eps_growth = (eps_1y - trailing_eps)/|trailing_eps| 는 전방/후행 기준쌍이라 별건 — 확인 필요."),
  proposed_repair = paste0(
    "anchor = max(sig-63L, basis_start) · basis_start = sig 이하 최근 동시변경일(>=50% live 변경). ",
    "오염 관측(d_now>=basis AND d_lag<basis)만 basis 이후 첫 관측으로 교체. 나머지 불변. ",
    "탐지기는 4월 한정 권장 — 원 탐지기는 초기 희소구간에서 4월 외 14일 오검출."),
  blocked_by = "none — 읽기 전용 실측 완료. factor_db 재빌드 결정만 남음",
  next_probe = list(
    "318개월 배치에 M26/M28 을 포함할지 vs M26/M28 만 선행 수리할지 — 재빌드 비용 대비 소비면(RAMP 프로브 3곳)이 좁으므로 선행 수리가 유리한지 실측",
    "수리 후 M26 이 canonical PORT_t 에서도 개선되는가 — FMB t 개선이 top-25 long-only 전이로 이어지는지(IC→PORT_t 전이 벽)"),
  artifacts = "stage_artifacts/infra/fq223_rollover_downstream_20260810/")

e2 <- list(
  id = sprintf("FQ-%d", nxt + 1L),
  title = "4·5월 횡단면 신호 계절성 — 롤오버와 무관한 return-side 현상 (M01 대조 실패에서 발견)",
  status = "measured_open", owner = "alpha-research", opened = "2026-08-10",
  category = "return_seasonality", parent = "FQ-223 (양성 대조가 실패해 드러남)",
  mechanism = paste0(
    "FQ-223 에서 '4·5월 제외' 를 롤오버 오염 제거 도구로 쓰려 했는데, 롤오버와 무관한 ",
    "M01_Mom_12_1(순수 가격 모멘텀)에서 **더 큰** 4·5월 효과가 나왔다: 4-팩터 FMB 에서 ",
    "t 1.951 → 0.613 (4·5월 제외), 4·5월 평균계수 0.01265 vs 평월 0.00107 (Welch p 0.0017). ",
    "C02_EPS_Chg_1m 도 t 2.709 → 1.556 (p 0.0237). M26 은 오히려 작다(t 2.555 → 2.222, p 0.486). ",
    "⇒ KR 4·5월은 횡단면 신호 전반이 잘 듣는 달이며, 그 효과 크기는 롤오버 노출과 **역순**이다."),
  why_it_matters = paste0(
    "① 방법론: '특정 달 제외' 를 데이터 결함의 통제로 쓰는 설계는 이 계절성과 교락된다 — ",
    "달-제외 통제를 쓰는 모든 라운드에 적용되는 제약. ② 알파: 계절성 자체가 미탐색 축이다."),
  next_probe = list(
    "4·5월 효과가 고립 봉우리인가 넓은 고원인가 — 슬라이딩 창(2·3·4개월)으로 재확인(feedback-sliding-window-before-bucket-claims 규약)",
    "결산·배당락·기관 리밸런싱 캘린더 중 무엇이 기전인가 — 12개월 계수 분해에서 2월(t 3.13)·10월(t 1.83)도 양이라 4월 단독 서사는 미성립"),
  caveat = "월별 n=23~24 (연 1회 관측) — 구조적 저검정력. 사전등록 전 required_effect_size.R 필수",
  artifacts = "stage_artifacts/infra/fq223_rollover_downstream_20260810/a1_month_of_year_decomp.csv, a1_exclusion_and_controls.csv")

Q$entries <- c(Q$entries, list(e1), list(e2))
Q$updated <- "2026-08-10"
write_frontier_queue(Q)

## ★재읽기 검증 (기록 후)
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
say("재읽기: 항목 %d (이전 %d · +%d) · 신규 id 존재 %s / %s",
    length(ids2), length(ids), length(ids2)-length(ids),
    e1$id %in% ids2, e2$id %in% ids2)
if (!all(c(e1$id, e2$id) %in% ids2)) stop("[d1] 큐 등재 재읽기 실패")
say("등재 완료: %s · %s", e1$id, e2$id)
say("★★FQ-223 판정 = %s", VERDICT)
