# =============================================================================
# emit_package_p7.R — WT-D20260808_003 alpha_package.json 발행
#   승계 원칙: hypothesis(mechanism / falsification / regime_scope)는 alpha_hypothesis.json
#   원문을 **재작성 없이** 옮긴다. schema 는 falsification 을 객체배열로 요구하므로
#   형식 전치(원문 문자열은 falsification_original_text 로 전량 보존)만 수행한다.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/emit_package_p7.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[emit] ", fmt, "\n"), ...))
source("02_Infrastructure/contracts/essence_score.R")

HYP <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
P0 <- readRDS(file.path(OUT, "p0_panels.rds")); M2 <- readRDS(file.path(OUT, "measure_p2.rds"))
A3 <- readRDS(file.path(OUT, "addendum_p3.rds")); C6 <- readRDS(file.path(OUT, "corrections_p6.rds"))
V  <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)
V2 <- fromJSON(file.path(OUT, "alpha_validation_addendum2.json"), simplifyVector = FALSE)
V3 <- fromJSON(file.path(OUT, "alpha_validation_dualbasis.json"), simplifyVector = FALSE)
X <- M2$X; cs <- M2$cs
say("INPUT X nrow=%d n_month=%d %s~%s · 승계 가설 verdict=%s",
    nrow(X), uniqueN(X$Date), min(X$Date), max(X$Date), HYP$verdict)
stopifnot(HYP$verdict == "designed")

# ── 1. alpha_scores.parquet + alpha_vector (수익 단위 보정) ──────────────────
zs <- function(v) { s <- sd(v, na.rm = TRUE); if (!is.finite(s) || s <= 0) rep(NA_real_, length(v)) else (v - mean(v, na.rm = TRUE))/s }
SC <- X[is.finite(q01_n), .(Date, Ticker, z_raw = q01, z_neutral = q01_n)]
SC[, z_neutral_std := zs(z_neutral), by = Date]
SLOPE_M <- M2$R$fmb$A2$slope_ann_pct / 1200      # 월 기대 active return per 1sd (A2 실측)
SC[, alpha_hat_monthly_active := z_neutral_std * SLOPE_M]
write_parquet(SC, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 %d개월 (alpha_hat = z_std × %.6f 월/1sd — A2 실측 기울기 보정)",
    nrow(SC), uniqueN(SC$Date), SLOPE_M)

last_d <- max(SC$Date)
TOP <- SC[Date == last_d][order(-z_neutral_std)][seq_len(min(25L, .N))]
alpha_vector <- setNames(as.list(round(TOP$alpha_hat_monthly_active, 6)), TOP$Ticker)
cov_cnt <- X[Date == last_d, .(Ticker, has_max5 = is.finite(max5), has_beta = is.finite(beta))]
TOPc <- merge(TOP[, .(Ticker)], cov_cnt, by = "Ticker", all.x = TRUE)
# confidence: 신호 강도(순위 백분위) × 데이터 가용성 × 라운드 전이 불확실성 감쇠
conf_base <- 0.35   # 본 라운드 = 전이 미확립(B2/B3) → 상한 억제
TOPc[, conf := pmin(1, pmax(0, conf_base * (1 + 0.4*as.numeric(has_beta) + 0.2*as.numeric(has_max5))))]
confidence_vector <- setNames(as.list(round(TOPc$conf, 3)), TOPc$Ticker)
say("alpha_vector %d종목 @ %s (월 기대 active %.4f~%.4f) · confidence %.2f~%.2f",
    length(alpha_vector), last_d, min(unlist(alpha_vector)), max(unlist(alpha_vector)),
    min(unlist(confidence_vector)), max(unlist(confidence_vector)))

# ── 2. alpha_inheritance_cor ────────────────────────────────────────────────
TUN <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
say("  tuned Factor_Name 실측: %s", paste(sort(unique(TUN$Factor_Name)), collapse = ", "))
BASE <- TUN[Factor_Name == "M01_PATHQ", .(Date = as.Date(Date), Ticker, m01 = score)]
stopifnot(nrow(BASE) > 0)   # 0 은 결론이 아니라 정지 신호
IC <- merge(SC[, .(Date, Ticker, z_neutral)], BASE, by = c("Date","Ticker"))
say("  inheritance 결합: %d행 %d개월", nrow(IC), uniqueN(IC$Date))
inh <- IC[, if (.N >= 10L && sd(z_neutral) > 0 && sd(m01) > 0) .(c = cor(z_neutral, m01, method = "spearman")) else .(c = NA_real_), by = Date][is.finite(c)]
stopifnot(nrow(inh) > 0)
inherit_cor <- abs(median(inh$c))
stopifnot(is.finite(inherit_cor))
say("alpha_inheritance_cor(중립 Q01 vs 기존 선별층 M01_PATHQ, 월별 Spearman 중앙 |·|) = %.3f", inherit_cor)

# ── 3. DSR (진단 — selection_type=chain 이라 게이트 아님) ───────────────────
bench_dt <- P0$bench_dt
pr <- as.data.table(cs$NEU25$period_returns)
a <- merge(pr[, .(Date = as.Date(date), ret_net)], bench_dt, by = "Date")[, act := ret_net - BM_Ret]
sr_ann <- mean(a$act)/sd(a$act)*sqrt(12)
dsr <- .essence_dsr(sr_ann, nrow(a), n_trials = 1L,
                    skew = mean((a$act-mean(a$act))^3)/sd(a$act)^3,
                    kurt = mean((a$act-mean(a$act))^4)/sd(a$act)^4)
say("DSR(진단, n_trials=1 chain) = %.4f · net active SR = %.3f", dsr, sr_ann)

# ── 4. 패키지 조립 ──────────────────────────────────────────────────────────
H <- HYP$selected
fals <- list(
  list(group_id = "A1_RAWDATA_OHLCVS_daily", field = "FDB-B2_registry_rawdata_price_daily",
       expectation = paste0("(F1 원문) 중립화 Q01 top-분위 바스켓의 trailing 60m β 가 유니버스 중앙값과 통계적 무차별(갭 |Δβ| < 0.05). ",
       "[실측 P0/P6: 중립 최상위분위 갭 -0.153 · top-25 갭 -0.209 (raw -0.245 / -0.269 대비 부분 소거). ",
       "월별 음(-) 비율 94.2% / 95.4%, 겹치지 않는 stride-60 부분표본 평균 -0.152 / -0.216. ",
       "→ 사전등록 B3 조건(|갭| > 0.15 잔존) 충족 = F1 REJECTED, 채널 귀속 주장 금지. ",
       "★겹치는 60m 창 계열이므로 NW lag-3 |t| 는 인용하지 않는다(부풀림 — lag-60 t -5.01 / -4.61)]")),
  list(field = "D03_EWMA", fields = list("A1_RAWDATA_OHLCVS_daily"),
       expectation = paste0("(F2 원문) MAX5 원변수 + vol63 을 횡단면 통제한 후 중립화 Q01 의 증분 순위정보 잔존. ",
       "[실측: 통제 후 기울기 연 +1.27% vs 통제 전 +1.22% → 잔존율 1.038 (사전 문턱 0.30 통과). ",
       "MAX5 단독 통제 +1.32%(t 2.06) · vol63 단독 +1.28%(t 2.21). ",
       "상위분위 Jaccard 중립Q01∩vol63 0.119 · ∩(-MAX5) 0.121, 월별 Spearman 중앙 +0.080 / +0.046 ",
       "→ vol/복권 축 재발견 아님. 부모 라운드 결손(MAX5 원변수 통제 부재) 해소]")),
  list(group_id = "A6_investor_flow_stock_daily", field_ref = "F2_investor_flow_stock_level",
       expectation = paste0("(F3 원문) 개인 순매수 집중이 raw z 가 아니라 중립화 z 의 하위에 부착되는가(연속 회귀, log시총 통제). ",
       "[실측: raw z 기울기 -0.0228 (t -4.34) · 중립 z -0.0126 (t -2.96), 부착 잔존율 0.55. ",
       "→ 중립 z 에도 유의 부착하나 절반 가까이가 제거된 성분에 있었다 = PARTIAL. ",
       "'제거된 성분은 무정보'라는 설계 전제를 부분 반증. 동시기 관측이며 예측 주장 아님(부모 라벨 승계)]")),
  list(field = "Q01_GPA", group_id = "FDB-B1_registry_fundamental_quarterly",
       expectation = paste0("(F4 예고 관측 원문) 중립화 z 5분위 평균수익 단조성 + rank-IC 병기 — Harvey-t 강한데 monotonicity < 0.5 지속이면 순위-평균 괴리 구조 지속(B2 예고). ",
       "[실측: 중립 rank-IC +0.0198 · NW t +4.95 · monotonicity 정본(10분위 Spearman) 0.648 / WT-001 용례(5분위 4스텝) 0.75. ",
       "→ 'Harvey-t>=3 AND monotonicity<0.5' 시그니처는 발화하지 않음. 그러나 수익-단위 상단은 별개: ",
       "top-분위 평균 active 차(중립-raw) -0.19%/yr (t -0.16), Q5-Q1 스프레드 차 -1.37%/yr (t -0.51)]")),
  list(group_id = "A2_universe_krx_monthly",
       expectation = paste0("(중립화 밴드 정의 원천) 섹터·사이즈 분류로 밴드 내 상대화가 실제 수행되었는가. ",
       "[실측: Sector UNKNOWN 0.00% · log(Size) NA 0.00% · 중립화 성공 81,349행/295개월 · raw-중립 월별 Spearman 중앙 0.664]")))

Q01_ESC <- list(escape_type = "STORED_SCORE",
  provenance = list(store_build_hash = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
    generator_code_path = "run_wt009_tuned.R — Q01_EB = MUL(z, DIV_GUARD(1, ADD(1, MUL(TS_STD(z,36), TS_STD(z,36)))))",
    generated_at = "2026-08-02T12:57"),
  production_parity_verified = FALSE)

PKG <- list(
  task_id = "WT-D20260808_003",
  as_of_date = "2026-08-08",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = H$hypothesis_description,
    mechanism = list(agent = H$mechanism$agent, friction = H$mechanism$friction, path = H$mechanism$path),
    falsification = fals,
    regime_scope = list(holds_in = H$regime_scope$holds_in,
                        weakens_or_reverses_in = H$regime_scope$weakens_or_reverses_in,
                        boundary_rationale = H$regime_scope$boundary_rationale),
    falsification_original_text = H$falsification$observable,
    falsification_reject_if_original = H$falsification$reject_if,
    inheritance_note = "mechanism / regime_scope / falsification 원문은 alpha_hypothesis.json(alpha-hypothesis, fable) 발행분을 재작성 없이 승계. schema 가 falsification 을 객체배열로 요구해 형식만 전치했고 원문 문자열은 falsification_original_text 에 전량 보존."),
  pit = list(sig_date = "2026-06-30", decision_ts = "2026-06-30",
             note = "패널 최신 월말. as_of_date 와의 차이는 팩터 패널 vintage lag"),
  factors = list(
    list(factor_id = "F1_Q01EB_sector_size_neutral",
      ast = list(op = "CS_NEUTRALIZE", args = list(
        list(leaf = "STORED_SCORE", escape_contract = Q01_ESC),
        "A2_universe_krx_monthly:Sector",
        list(op = "LOG", args = list(list(leaf = "A2_universe_krx_monthly:Size"))))),
      role = "core_signal", restatement_exposure = 1L),
    list(factor_id = "F2_ctrl_MAX5",
      ast = list(op = "CS_ZSCORE", args = list(
        list(op = "TS_MEAN", args = list(
          list(op = "TS_MAX", args = list(list(leaf = "A1_RAWDATA_OHLCVS_daily:Close"), 21)), 5)))),
      role = "diagnostic_control", restatement_exposure = 0L),
    list(factor_id = "F3_ctrl_vol63",
      leaf_ref = "FDB-B2_registry_rawdata_price_daily",
      role = "diagnostic_control", restatement_exposure = 0L)),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
      list(leaf = "STORED_SCORE:Q01_EB", availability_rule = "fixed: 월말 z + trailing 36m 분산(당월 미포함). 기저 재무는 quarterly 45d / annual 익년 3/31(C4 2026-07-25)", restatement_prone = TRUE),
      list(leaf = "A2_universe_krx_monthly:Sector", availability_rule = "fixed: 월말 스냅샷 분류 — 당월 말 시점 확정", restatement_prone = FALSE),
      list(leaf = "A2_universe_krx_monthly:Size", availability_rule = "fixed: 월말 시가총액 — t-1 종가 기준", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Close", availability_rule = "fixed: t-1 종가. MAX5 는 신호월 내 일간만 사용(홀딩월 시작 전)", restatement_prone = FALSE),
      list(leaf = "FDB-B2_registry_rawdata_price_daily", availability_rule = "fixed: trailing 63d EWMA vol, 당월 미포함", restatement_prone = FALSE)),
    verdict = "warn_restatement",
    notes = paste0("Q01_EB 는 재무 기반이라 restatement 노출. lag1 스트레스 실측: 중립 z 기울기 잔존율 0.574(부호 유지·크기 감소 = 정상 감쇠, 급증 아님) → 동월 누출 징후 없음. ",
      "C5: 신호는 홀딩월 시작 전 월말 d0 정보만. 벤치·수익은 build_monthly_forward_returns 계약 경유.")),
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260808_003/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family = "Quality/EarningsStability",
      proxy = "Q01_EB_neutral (섹터+log시총 잔차화 EB-shrunk GPA)",
      formula = "resid( Q01_EB ~ log(Size) + factor(Sector) ), 월별 횡단면",
      lag_rule = "quarterly 45d 상속 + trailing 36m 분산, 월말 산출",
      winsorization = "none (EB shrink 내장)", neutralization = "sector+size",
      economic_rationale = "behavioral", weight_theta = 1,
      references = list("WT-D20260808_001 A6 (중립화 rank-IC 1.28배)", "WT-D20260802_009 Q01_EB 정의"),
      economic_rationale_detail = "밴드 내 이익불안정 종목의 성장 서사 과대평가(개인 수요) — 구조적 섹터·사이즈 안정성 격차를 제거하고 밴드-내 상대 성분만 남긴다",
      redundancy_cluster_id = "quality_stability_neutralized / KR_Q01_family",
      redundancy_evidence = "vol63 상위분위 Jaccard 0.119 · (-MAX5) 0.121 · 월별 Spearman 중앙 +0.080/+0.046 → FQ-092 vol family 와 중복 아님. 기존 선별층 M01_PATHQ 대비 |Spearman| 중앙 0.02 미만"),
    list(factor_family = "Volatility/Lottery", proxy = "MAX5 (월내 상위 5일 평균 일수익)",
      formula = "mean(top5 daily return within signal month)", lag_rule = "daily t-1, 월말 산출",
      winsorization = "none", neutralization = "none", economic_rationale = "behavioral",
      weight_theta = 0, references = list("Bali-Cakici-Whitelaw 2011", "WT-020 MAX5 소멸 실측"),
      economic_rationale_detail = "F2 재발견 배제 통제 변수 — alpha 성분 아님(weight 0)",
      redundancy_cluster_id = "vol_lottery_family_FQ092")),
  diagnostics = list(
    canonical_port_t_nw_lag3 = cs$NEU25$portfolio_alpha_t_nw_lag3,
    canonical_port_t_pvalue = cs$NEU25$portfolio_alpha_t_pvalue,
    canonical_n_months = as.integer(cs$NEU25$n_months),
    canonical_port_t_raw_arm = cs$RAW25$portfolio_alpha_t_nw_lag3,
    canonical_port_t_base_M01 = cs$BASE$portfolio_alpha_t_nw_lag3,
    canonical_port_t_filter_arm = cs$FILT_NEU$portfolio_alpha_t_nw_lag3,
    rank_ic = M2$Qn$rank_ic, icir = M2$Qn$icir, harvey_t_stat = M2$Qn$harvey_t_nw,
    rank_ic_raw_arm = M2$Qr$rank_ic, harvey_t_stat_raw_arm = M2$Qr$harvey_t_nw,
    monotonicity = C6$monotonicity$q01_n$monotonicity_platform_q10_spearman,
    monotonicity_definition = "platform canonical — 10분위 평균수익 vs 분위순위 Spearman (ml_pipeline/quality_metrics.py:77-98). 범위 [-1,1]",
    monotonicity_q5_stepfrac_wt001 = C6$monotonicity$q01_n$monotonicity_q5_stepfrac_wt001,
    monotonicity_q5_stepfrac_definition = "WT-001 용례 — 5분위 인접 4스텝 증가비율, 범위 {0,.25,.5,.75,1}. 정본과 척도가 달라 분리 기록",
    decile_mean_ann_pct = C6$monotonicity$q01_n$decile_mean_ann_pct,
    subperiod_stability = 0.6667,
    subperiod_stability_note = "3분기 중 rank-IC 양(+) 유지 비율 — 중립 신호는 pre-2015 +0.0245 / post-2015 +0.0146 양쪽 양(+), 전표본 대비 raw(pre +0.0327 / post -0.0025) 와 대비",
    turnover_proxy = cs$NEU25$turnover_annual,
    turnover_filter_arm = cs$FILT_NEU$turnover_annual,
    net_sr_neutral_top25 = cs$NEU25$net_sr,
    deflated_sharpe_ratio = dsr,
    deflated_sharpe_note = "진단 산출. selection_type=chain(가설주도 순차, n_trials=1) → measurement-graduation §3 상 DSR 게이트 부적용",
    post_neutralization_ic = M2$Qn$rank_ic,
    alpha_inheritance_cor = inherit_cor,
    alpha_inheritance_cor_note = "중립 Q01 vs 기존 선별층 M01_PATHQ 월별 Spearman 중앙 |·|. < 0.95 → wt_type=discovery 유지",
    fmb_slope_ann_pct_neutral = M2$R$fmb$A2$slope_ann_pct,
    fmb_slope_t_nw_neutral = M2$R$fmb$A2$t_nw,
    fmb_slope_ann_pct_raw = M2$R$fmb$A1$slope_ann_pct,
    fmb_slope_t_nw_raw = M2$R$fmb$A1$t_nw,
    fmb_slope_ann_pct_neutral_ctrl_MAX5_vol63 = M2$R$fmb$A3$slope_ann_pct,
    fmb_slope_t_nw_neutral_ctrl_MAX5_vol63 = M2$R$fmb$A3$t_nw,
    post2015_rank_ic_neutral = A3$B4_direct$q01_n_post2015$ic,
    post2015_rank_ic_neutral_t = A3$B4_direct$q01_n_post2015$t_nw,
    post2015_rank_ic_raw = A3$B4_direct$q01_post2015$ic,
    post2015_rank_ic_raw_t = A3$B4_direct$q01_post2015$t_nw,
    post2015_top25_active_ann_pct_capw = V3$arms$q01_n_top25_post2015$capw_ann_pct,
    post2015_top25_active_t_capw = V3$arms$q01_n_top25_post2015$capw_t,
    post2015_top25_active_ann_pct_ew = V3$arms$q01_n_top25_post2015$ew_ann_pct,
    post2015_top25_active_t_ew = V3$arms$q01_n_top25_post2015$ew_t,
    harvey_t_specs_pass_count = 1L,
    harvey_t_specs_pass_count_note = "rank-IC NW t 4.95 만 3.0 통과. portfolio-alpha t 는 전 arm 미달 — 두 통계량 분리 보고(Cycle 2 교훈)",
    metric_type = "canonical_screen (arm) / diag (배터리·구조 관측)",
    selection_type = "chain",
    n_trials_cumulative = 1L),
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  challenge_flags = list(
    "★B3 발화(사전등록) — 중립화가 β 갭을 부분만 닫는다(분위 -0.245→-0.153 · top-25 -0.269→-0.209, 문턱 -0.15 잔존). 섹터+사이즈는 β 채널을 span 하지 못하며 전이 결과의 채널 귀속 주장은 금지된다. C3(β-직접 잔차화)는 재설계 후보로만 승격, 본 라운드 arm 추가 없음",
    "★handoff 제1 조건 이행 — paired 형태 2종을 착수 전 폐기(필요 연 4.00%/2.81% vs drag 함의 0.69%/0.12%). 판정 형태를 월-횡단면 FMB 로 전환. 부모 라운드 전 arm INCONCLUSIVE_UNDERPOWERED 재발 회피",
    "★자본 자격 주장 없음 — 중립 top-25 canonical PORT_t +0.382 (HARD 2.95 대비 크게 미달). 필터 arm 2.308 도 미달. 본 라운드는 벽-귀속 판별 라운드",
    "★전이 벽의 직접 관측(본 라운드 최대 산출) — post-2015 중립 Q01 rank-IC +0.0146 NW t +2.72 (양(+) 유의)인데 같은 창 top-25 바스켓 active 는 cap-w -12.13%/yr t -2.38 · EW-유니버스 -5.72%/yr t -2.29 (양쪽 basis 에서 음(-) 유의). 순위 정보와 상단-평균 수익이 같은 창에서 반대 부호로 동시에 유의한 최초 실측",
    "★B4 부활 조건 발화 — FQ-122 부활 조건 'post-2015 양(+) 회복'은 중립 신호에서 rank-IC 축으로 충족(raw -0.0025 t -0.31 → 중립 +0.0146 t +2.72, paired 차 +0.0171 t +2.39). 단 사전등록 판정인 연속 시간추세는 비유의(중립 -0.00033/yr t -0.50) — '회복'이 아니라 '감쇠 정지'가 정확한 서술. 자본 경로 자격은 상단-수익 음(-)으로 별도 차단",
    "★정보 증가 vs 노이즈 축소 — 3종 절차 결과가 갈린다. d1(수익-단위 스프레드): 중립-raw -1.37%/yr t -0.51 = 확대 없음(노이즈 축소 쪽). 절사 사다리에서 중립만 t 1.62→3.07 로 상승 = 전형적 분모 효과. d2(canonical 분해): Δmean +2.34%p · ΔSE -7.6% = 분자 쪽(정보 증가 쪽)이나 저검정력. d3(F3): 부착 잔존율 0.55 = 부분 지지. 종합 처분 = alpha lane 단독 승격 불가, risk/monitoring 소비 라벨 병행",
    "★F3 부분 반증 — 개인 순매수 시그니처의 45%가 중립화로 제거된 성분에 있었다(raw -0.0228 t -4.34 → 중립 -0.0126 t -2.96). '제거되는 성분은 무정보'라는 설계 전제가 부분적으로 틀렸다. 승계 mechanism 의 결함이며 재작성하지 않고 challenge_note 로 보고(Charter 원칙 8)",
    "★상단/하단 분해 — Q5-Q1 스프레드 축소는 하단에서 온다(중립 하위분위 -1.66%/yr vs raw -2.84%/yr, Δ +1.18%). 중립화가 좌측 꼬리 판별력을 잃는다 = 제외필터면(부모 소비면)에는 불리. 필터 arm paired +0.55%/yr t 0.44 (부모 raw 필터 +1.25% t 0.84 보다 약함, 둘 다 저검정력)",
    "★F2 통과(재발견 배제 성립) — MAX5 원변수 통제는 부모 라운드가 명시한 결손이었고 본 라운드가 해소했다. 잔존율 1.038, Jaccard 0.12 수준 → FQ-092 vol QUARANTINE family 재포장 아님",
    "★창-정합 통제 — A4(β 통제, n=259)가 A2(n=295)보다 약해 보이는 것은 β 통제가 아니라 표본이다. 동일 창에서 β 통제 순효과 1.287(오히려 강화), 표본 효과 0.449. 서로 다른 창의 수치를 나란히 놓고 통제 효과로 읽지 말 것",
    "★겹치는 창 위 짧은 NW lag 금지(2026-08-09 정정) — β 갭 계열은 trailing 60m 이 매월 59개월 겹친다(ACF r1 0.86~0.93). 본 산출물은 |t| 를 인용하지 않고 점추정·월별 부호 일관성·stride-60 으로 서술한다. 참고 정정치: 중립 분위 갭 lag-3 t -13.20 → lag-60 t -5.01, Bartlett 유효 n 20.2/259",
    "★paired Δβ top-25(+0.059)는 정정 추론에서 비유의(lag-60 t +1.74 · stride-60 t +1.34) — '중립화가 top-25 의 β 를 올렸다'는 주장은 분위 수준(+0.091)에서만 성립",
    "monotonicity 정의 충돌 처리 — diagnostics.monotonicity 는 플랫폼 정본(10분위 Spearman, 중립 0.648)이고 WT-001 용례(5분위 4스텝, 0.75)는 별도 필드. 두 척도의 값 범위가 다르므로 문헌값 비교 시 정의 확인 의무",
    "STORED_SCORE Q01_EB 는 production_parity_verified=false (연구 파생 패널) — incumbent base 소비 불가. 본 라운드는 base 비교가 아니라 신호 자체의 프로파일 측정이라 §7b 저촉 없음",
    "국면 상호작용은 전부 ADVISORY·비유의 (중립 기울기 × 벤치 trailing12 +1.03%/1sd t 0.98 · × 개인 강도 +0.68% t 0.94). 승계 가설의 위기월 부호 반전 예측은 검정력 부족으로 확인도 반증도 못 함 — '효과 없음' 단정 금지",
    "동시기 관측 라벨 유지 — F3 개인 순매수는 인과 아님(부모 승계)",
    "RF-A3 점검: recent 3Y ICIR 별도 산출 미실시(분할 금지 mandate 하에서 3Y 창은 유효표본 36으로 구조적 저검정력) — 시기 축은 연속 추세 + post-2015 서술로 대체"))

write_json(PKG, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
say("alpha_package.json 발행 → %s", file.path(MBX, "alpha_package.json"))

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260808_003", package_type = "alpha_package",
  method_selected = "Q01_EB sector+size neutralized — 월-횡단면 FMB 판정(paired 형태 착수 전 폐기)",
  input_file_paths = c("stage_artifacts/WT_D20260802_009/tuned_panel.parquet",
    "stage_artifacts/WT_D20260802_009/sector_panel.parquet",
    "stage_artifacts/WT_D20260802_009/size_panel.parquet",
    ".cache/RAWDATA.parquet", ".cache/investor_stock/investor_individual.parquet",
    "qepm/mailbox/worktask/WT-D20260808_003/alpha_hypothesis.json"))
say("lineage 기록 완료 (write_json → record_package_lineage 순서 준수, L-194)")
