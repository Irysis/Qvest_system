## build_wt003_alpha_package.R — WT-D20260802_003 alpha_package (AST v1.1) + validation + lineage + telegram
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest); library(dplyr)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_003"
MB  <- "qepm/mailbox/worktask/WT-D20260802_003"
stopifnot(dir.exists(MB))

full <- readRDS(file.path(OUT, "wt003_full_20260802.rds"))
adv  <- readRDS(file.path(OUT, "wt003_adversarial_checks.rds"))
res <- full$res; TAB <- full$TAB; PAIRED <- full$PAIRED; PR <- full$PR
COMP_final <- full$COMP_final; AN <- full$ANCH_last

final_date <- max(as.Date(COMP_final$signal_date))
cat(sprintf("final sig_date=%s | %d tickers scored\n", final_date, nrow(COMP_final)))

## ── 최종 anchor theta (W_portt: clip-at-zero trailing NW-t 비례) ──
POOL <- AN$pool
tt <- AN$tt[POOL]; v <- pmax(tt, 0); v[!is.finite(v)] <- 0
theta <- if(sum(v)<=0) setNames(rep(1/length(POOL), length(POOL)), POOL) else setNames(v/sum(v), POOL)

## ── Grinold 스케일: alpha_i = IC * sigma_cs * z_i (IC=실측 rank_ic, sigma_cs=trailing 36m 횡단면 월수익 sd 평균) ──
rank_ic <- as.numeric(res$advisory_w_portt$rank_ic)
rd <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","K200","KQ150")))
rd[, Date := as.Date(Date)]
me_all <- sort(unique(rd[, .(ym=format(Date,"%Y%m"), Date)][ , .(me=max(Date)), by=ym]$me))
me_use <- tail(me_all, 38L)
rdm <- rd[Date %in% me_use & (K200==TRUE | KQ150==TRUE) & !is.na(Close) & Close>0]
rm(rd); invisible(gc())
setorder(rdm, Ticker, Date)
rdm[, Ret_1m := Close/shift(Close) - 1, by=Ticker]
rdm <- rdm[is.finite(Ret_1m) & Ret_1m > -1 & Ret_1m < 5]
sig_cs_tbl <- rdm[, .(s=sd(Ret_1m, na.rm=TRUE), n=.N), by=Date][n>=50]
sigma_cs <- mean(tail(sig_cs_tbl[order(Date)], 36L)$s)
cat(sprintf("sigma_cs (trailing 36m 횡단면 월수익 sd 평균) = %.4f | rank_ic = %.4f\n", sigma_cs, rank_ic))

A <- copy(COMP_final)[, .(Ticker=security_id, z=score)]
A[, alpha := round(rank_ic * sigma_cs * z, 6)]

## ── confidence: 최종월 pool 20팩터 커버리지 비율 → [0.30, 0.95] 스케일 ──
ps <- open_dataset("outputs/ramp/pure_factor_scores.parquet") |>
  dplyr::filter(signal_date == final_date, factor_id %in% POOL) |>
  dplyr::select(security_id, factor_id, z) |> dplyr::collect()
ps <- as.data.table(ps)
cov_t <- ps[!is.na(z), .(n_cov=uniqueN(factor_id)), by=security_id]
A <- merge(A, cov_t[, .(Ticker=security_id, n_cov)], by="Ticker", all.x=TRUE)
A[is.na(n_cov), n_cov := 0L]
A[, confidence := round(0.30 + 0.65 * n_cov/length(POOL), 3)]

## ── inheritance/redundancy cor (active 시계열 기준, basis 라벨) ──
cor_series <- function(a, b){ if(is.null(PR[[a]])||is.null(PR[[b]])) return(NA_real_)
  m <- merge(PR[[a]][,.(date,x=act_bm)], PR[[b]][,.(date,y=act_bm)], by="date")
  round(cor(m$x, m$y, use="complete.obs"), 4) }
cor_vs_ppure <- NA_real_   # Ppure_rebuild pr 시계열 미보존(러너 RES만 저장) — 정직 미측정 라벨. membership 수준 증거 = Jaccard 0.32
cor_vs_base  <- cor_series("W_portt", "base")
cat(sprintf("active-cor: W_portt vs base=%.3f | vs Ppure=미측정(pr 미보존)\n", cor_vs_base))

pval <- round(2*pt(-abs(res$w_portt_capwt), df=220), 4)
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }

factor_specs <- lapply(POOL, function(f) list(
  factor_family = fam_of(f), proxy = f,
  formula = "factor DB Z_Score_Aligned (pure_factor_scores z, load_month_factors parity)",
  lag_rule = "factor DB PIT (C13 direction / C14 IC Usable_Date)",
  winsorization = "factor DB 표준", neutralization = "none (cross-sectional z-score)",
  economic_rationale = sprintf("%s family — trailing 36m ICIR top-20 선별(기존 relevance 규율), 가중은 trailing 배포권 PORT_t 정렬", fam_of(f)),
  weight_theta = round(as.numeric(theta[f]), 4),
  source = "db_existing",
  references = list("Grinold-Kahn 1999 (IC 가중 이론 — 대조군 W_icir 근거)")))

tab_of <- function(m) as.list(TAB[model==m, .(port_t_capwt, port_t_EWuni, oos_retention, calmar, turnover, n_months)])
paired_of <- function(m, b) PAIRED[model==m & base==b & basis=="act_bm", paired_t][1]

challenge_flags <- list(
  list(id="CF-1", severity="HIGH",
       flag="graduation FAIL — cap-w PORT_t 1.338 < 2.95 HARD, oos_retention -0.407 < 0.5 무조건 FAIL(decay-pattern: post-2017 cohort 감쇠), calmar 0.396 < 0.64. 자본 후보 아님"),
  list(id="CF-2", severity="HIGH",
       flag="construction 천장 미달 — 1.338 vs 2.937 (d=-1.599). WT 판정 본체 기준 config-scoped negative"),
  list(id="CF-3", severity="MEDIUM",
       flag="subperiod IC 불안정 0.22 < 0.5 (RF-A1 유형: 중기 2015-19 IC 0.0175 침하) + 본 가설은 내부 실측 기반(외부 논문 0편)"),
  list(id="CF-4", severity="INFO",
       flag="저장 파생 패널(r6_factor_deployzone_active) 소비 — lag-1 스트레스 통과(paired 2.569→2.481 무붕괴)로 동월 누출 반증. 패널 provenance: 07-14 재빌드 byte-parity, canonical parity 검증"),
  list(id="CF-5", severity="INFO",
       flag="개선 기전 귀속: theta 희소성 median 1/20 (soft-선별 아님, intensity 효과 실재) + Jaccard(ICIR풀, Ppure풀)=0.32 (membership 미수렴) — 잔여 갭 1.34→2.61은 membership(선별) 귀속"),
  list(id="CF-6", severity="INFO",
       flag="대안 가설 기록(Step 0): (a) PORT_t-정렬 가중을 비-return 패널(insider)에 적용 (b) 가중형 sqrt 완만화 (c) 선별+가중 동시 정렬 재구성 — 본 라운드는 귀속 격리 위해 가중 단독"))

method_shopping_log <- list(alpha_agent = list(
  candidates_tried = 5L,
  parallel_exec = FALSE, n_workers = 1L,
  method_log = list(
    list(name="base_icir_EW",  canonical_port_t=TAB[model=="base",port_t_capwt],     selected=FALSE, note="대조군(2x2 좌상단 셀)"),
    list(name="W_famfix",      canonical_port_t=TAB[model=="W_famfix",port_t_capwt], selected=FALSE, note="고정가중(가족균등) 대조 — base 대비 paired -0.97"),
    list(name="W_icir",        canonical_port_t=TAB[model=="W_icir",port_t_capwt],   selected=FALSE, note="relevance-정렬 가중 대조 — paired +0.89 비유의"),
    list(name="W_portt",       canonical_port_t=TAB[model=="W_portt",port_t_capwt],  selected=TRUE,  note="★가설 arm(사전지정 유일 채택후보) — paired +2.569 유의"),
    list(name="W_ivar",        canonical_port_t=TAB[model=="W_ivar",port_t_capwt],   selected=FALSE, note="inverse-variance(NCO 단순형 대리) 대조 — paired -0.01"))))

alpha_package <- list(
  task_id = "WT-D20260802_003",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = as.character(final_date),
             decision_ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  hypothesis = list(
    statement = "멀티팩터 조합의 가중(theta)을 realized-PORT_t(배포권 top-25 실현 net active NW-t) 정렬로 결정하면, 기존 relevance 규율(trailing ICIR)로 선별된 풀에서 EW/고정/relevance 가중 대비 실현 portfolio-alpha가 개선된다. 선별 아크 R4~R13이 선별 slot에서 확립한 '게이트-정렬 라벨 지배' 원리의 가중 slot 일반화 검증.",
    mechanism = list(
      agent = "리서치 파이프라인의 조합 가중 결정 관행 — 횡단면 순위력 통계(IC/ICIR)와 배포 실현 성과(top-25 long-only net active) 사이 목적함수 불일치를 만든 주체",
      friction = "IC→PORT_t 전이 벽: cap-tier 국소화(알파가 벤치 저비중 MID/OTHER tier에 국소) + 거래비용 15bps + top-25 협소 전이층 때문에 relevance 통계가 배포 성과를 대표하지 못하며, 이 괴리는 long-only 제약 하에서 차익거래로 지워지지 않음",
      path = "가중을 trailing 실현 배포성과에 정렬하면 전이-생존 팩터에 합성 계수가 집중되어 top-25 선택이 실현 active 원천으로 이동, 월간 리밸런싱 주기로 반영"),
    falsification = list(
      list(field = "S01_Size",
           condition = "theta=0으로 클립된(trailing PORT_t<=0) ICIR-상위 팩터들의 top-25 보유가 Size 랭킹 MEGA tier에 과대노출되지 않으면 — 즉 IC→PORT_t 괴리가 cap-구성으로 설명되지 않으면 — friction(cap-tier 국소화) 기각"),
      list(fields = as.list(head(names(sort(theta, decreasing=TRUE)), 5)),
           condition = "가중 상위 팩터의 trailing 36m 배포권 active 순위 자기상관이 0에 수렴하면(성과 지속성 부재) 정렬 가중의 path 기각 — R6 실측 0.86~0.92 지속성이 전제")),
    regime_scope = list(
      holds_in = list("neutral", "expansion (팩터 리더십 지속 국면)"),
      weakens_or_reverses_in = list("crisis", "crisis 직후 V-반등 (팩터 리더십 반전 국면)"),
      boundary_rationale = "trailing 36m 창은 리더십 반전을 후행 반영 — 반전 국면에서 정렬 가중은 직전 승자에 과배분(팩터 모멘텀 크래시 유형). 실측 post-2017 감쇠(post17 t=-1.05)와 정합")),
  factors = c(
    lapply(POOL, function(f) list(
      factor_id = f,
      ast = list(leaf = f),
      role = "core_signal",
      restatement_exposure = 0L)),
    list(list(
      factor_id = "WGEN_trailing_portt",
      ast = list(leaf = "SPECIAL_OP",
                 escape_contract = list(
                   escape_type = "SPECIAL_OP",
                   op_code_path = "stage_artifacts/WT_D20260802_003/run_wt003_weighting_ab.R (theta_of: W_portt = clip-at-zero trailing NW-t 비례, 창 [a-36,a-1], cadence 6m)",
                   walk_forward = TRUE)),
      role = "combination_weight_generator",
      restatement_exposure = 0L))),
  combination_rule = "z_score_aligned_weighted_sum",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "pure_factor_scores.z (102 approved factors)",
           availability_rule = "load_month_factors parity (R6 prereg provenance max|d|=0) — C13/C14/C15 준수",
           restatement_prone = FALSE),
      list(leaf = "r6_factor_deployzone_active.parquet (trailing 가중 재료 — 저장 파생 패널)",
           availability_rule = "active(s) = s월 점수→s+1월 실현수익. anchor a 소비 창 [a-36,a-1]은 a 시점 실현완료분만. lag-1 스트레스 무붕괴(2.569→2.481)로 동월 누출 반증. 07-14 재빌드 byte-parity",
           restatement_prone = FALSE),
      list(leaf = "RAWDATA:Ret/Close (forward return 실측)",
           availability_rule = "t-1 거래일 확정치, R44 sanity 방화벽 경유",
           restatement_prone = FALSE)),
    verdict = "clean"),
  alpha_vector = setNames(as.list(A$alpha), A$Ticker),
  confidence_vector = setNames(as.list(A$confidence), A$Ticker),
  signal_matrix_ref = "stage_artifacts/WT_D20260802_003/alpha_scores.parquet",
  factor_specs = factor_specs,
  diagnostics = list(
    canonical_port_t_nw_lag3 = round(res$w_portt_capwt, 4),
    canonical_port_t_pvalue = pval,
    canonical_n_months = 221L,
    metric_type = "canonical_screen",
    rank_ic = round(rank_ic, 4),
    icir = round(as.numeric(res$advisory_w_portt$icir), 4),
    monotonicity = round(as.numeric(res$advisory_w_portt$monotonicity), 4),
    subperiod_stability = round(as.numeric(res$advisory_w_portt$subperiod_stability), 4),
    turnover_proxy = round(TAB[model=="W_portt", turnover], 4),
    harvey_t_stat = round(as.numeric(res$advisory_w_portt$harvey_t), 4),
    post_neutralization_ic = NULL,
    post_neutralization_note = "중립화 미수행(pure factor z 기존 처리 소비) — 별도 sector/size 중립화는 risk 단계 판단 존중",
    paired_primary_t_vs_base = round(as.numeric(res$primary_paired), 4),
    paired_vs_Wicir_t = round(paired_of("W_portt","W_icir"), 4),
    ceiling_capw = 2.937, ceiling_gap = round(res$vs_ceiling, 4),
    dual_basis = res$dual_basis_w_portt,
    dsr_diag = list(raw = TAB[model=="W_portt", dsr_raw], penalized_ntrials4 = TAB[model=="W_portt", dsr_pen],
                    note = "chain — DSR 게이트 부적용(진단 산출). n_trials_wt=4, substrate 계보 별도 표기"),
    alpha_inheritance_cor = NULL,
    alpha_inheritance_note = "parent 없음(discovery). redundancy: vs Ppure(최근접 계보) active-cor는 pr 시계열 미보존으로 미측정 (검증 안 됨 — risk 단계 재측정 TBD). membership 수준 증거 = Jaccard(양-theta, Ppure풀) 0.34 / 풀 자체 0.32. incumbent book(STR_1715 계보) 대비 cor은 production-parity 요건(§7b)상 risk/judge 단계 소관",
    redundancy_active_cor_vs_ppure = cor_vs_ppure,
    redundancy_active_cor_vs_base_icir = cor_vs_base,
    redundancy_cluster_id = "multifactor_composite_KR102 (P-pure 계보 인접 — active-cor 기준 구분 실측)"),
  alpha_discovery_count = 1L,
  selection_objective = "canonical_port_t",
  selection_type = "chain",
  selection_type_rationale = "가설 arm(W_portt) 단독을 사전등록 채택후보로 지정, 나머지 3+1은 대조군(채택 불가) — 열거 argmax 아님. IS-only: trailing 통계는 구조적으로 과거-only, OOS 반복조회 없음. iteration 없음(1-shot A/B)",
  n_trials_wt = 4L,
  method_shopping_log = method_shopping_log,
  challenge_flags = challenge_flags)

write_json(alpha_package, file.path(MB, "alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, null="null")
cat(sprintf("alpha_package.json written (%d bytes)\n", file.size(file.path(MB,"alpha_package.json"))))

## lineage (Step 2 — write 후)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_003",
  package_type = "alpha_package",
  method_selected = "W_portt: trailing ICIR top-20 선별(고정) x clip-at-zero trailing PORT_t 정렬 가중 (2x2 미검 셀)",
  input_file_paths = c("outputs/ramp/pure_factor_scores.parquet",
                       "outputs/ramp/r6_factor_deployzone_active.parquet",
                       "outputs/ramp/factor_group_scores.parquet",
                       ".cache/rawdata.parquet",
                       "06_Registry/ramp/approved_factor_library.parquet"))
cat("lineage recorded\n")

## alpha_validation.json (stage_artifacts)
validation <- list(
  task_id = "WT-D20260802_003", as_of = "2026-08-02",
  config_hash = res$config_hash,
  prereg_file = "stage_artifacts/WT_D20260802_003/wt003_prereg_20260802.json",
  harness_parity = res$parity,
  gates_by_arm = lapply(setNames(nm=TAB$model), tab_of),
  paired = PAIRED[basis=="act_bm"],
  primary = list(criterion = "paired NW-t(cap-w) W_portt vs base >= 2.0",
                 value = as.numeric(res$primary_paired), pass = !res$kill),
  verdict = list(
    mechanism_finding = "POSITIVE — 가중 slot의 PORT_t-정렬은 relevance-선별 풀에서 유의 개선(paired +2.569). 2x2 완성: 정렬 정보는 '없는 곳'에 주입 시 유효, '이미 있는 곳'(R10)엔 중복(null)",
    graduation = "FAIL — PORT_t 1.338<2.95 / oos -0.407<0.5 무조건 FAIL / calmar 0.396<0.64",
    ceiling = "config-scoped negative — 천장 2.937 대비 -1.599. 정렬 정보의 지배적 carrier = membership(선별). 가중 slot 주입은 부분 회복(0.59→1.34)에 그침",
    label = "screen-tier 미달 — 단 기전 지식(가중 slot 정렬 유효성)은 Ledger 적립 가치"),
  adversarial_checks = list(
    lag1_stress = adv$lag1,
    theta_sparsity = list(zero_theta_mean = mean(adv$zero_theta), zero_theta_median = median(adv$zero_theta),
                          n_eff_mean = mean(adv$n_eff)),
    jaccard_postheta_vs_ppure = mean(adv$jaccard_postheta_ppure, na.rm=TRUE),
    jaccard_pools = mean(adv$jaccard_pools, na.rm=TRUE)),
  cap_tier = res$concentration,
  dual_basis_w_portt = res$dual_basis_w_portt,
  universe_comparison = list(
    performed = FALSE,
    note = "L-227 v2 비교 mandate는 ICIR attenuation 진단(ICIR<0.15 등) 시 발동 — 본 라운드 rank_ic 0.0601/ICIR 0.474로 미해당. universe = KR_top342 계열(K200∪KQ150), cost 15bps"),
  measurement = list(metric_type = "canonical_screen", top_n = 25L, cost_bps = 15, liq_min = 2e8,
                     n_months = 221L, period = "2008-01 ~ 2026-05 신호(수익 2026-06까지)",
                     note = "2026-06 신호월(7월 폭락 수익)은 factor_group_scores 신호달력 말단 제약으로 측정 미포함 — emit 알파는 2026-06-30 신호"))
write_json(validation, file.path(OUT, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=5, null="null")
cat("alpha_validation.json written\n")

## ── 차트 + 텔레그램 ──
tg_ok <- tryCatch({
  source("02_Infrastructure/telegram/tg_chart_pack.R")
  pr_w <- PR[["W_portt"]][, .(date, ret_net, benchmark_ret)]
  p1 <- tg_chart_pack(pr_w, out_dir = OUT, title = "WT003 PORT_t 정렬가중 멀티팩터",
                      metrics_note = sprintf("canonical PORT_t %.2f | paired vs EW +%.2f | 회전율 %.1f/yr",
                                             res$w_portt_capwt, as.numeric(res$primary_paired),
                                             TAB[model=="W_portt", turnover]))
  p2 <- tg_chart_sweep(labels = TAB$model, values = TAB$port_t_capwt, out_dir = OUT,
                       title = "WT003 가중규칙별 canonical PORT_t (cap-w)",
                       value_label = "PORT_t (NW lag-3)", hline = 2.95, hline_label = "HARD 2.95",
                       highlight = "W_portt")
  source("02_Infrastructure/telegram/telegram_notify.R")
  tg_agent_brief(
    agent = "Alpha",
    title = "WT-D20260802_003 ALPHA_DONE — 가중 정렬 유의(+2.57) · 천장 미달(1.34<2.94)",
    sections = list(
      list(type = "summary", emoji = "📌",
           body = "멀티팩터 조합에서 '얼마나 섞을지'(가중)를 실현 성과 기준으로 정하면 등가중보다 유의하게 좋아짐을 확인 — 다만 절대 성과는 자본 기준 미달이라 편입 후보는 아님."),
      list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
           items = c("시도: 팩터를 '고르는' 기준이 아니라 '섞는 비율'을 실제 포트 성과 기준으로 정하는 마지막 미검 조합을 시험했습니다",
                     "방법: 동일한 팩터 20개 위에서 가중 규칙 4종만 바꿔 221개월 실측 비교(다른 조건 전부 동일)했습니다",
                     "결과: 실현성과-정렬 가중이 등가중 대비 통계적으로 유의하게 우수(paired t +2.57)",
                     "한계: 절대 성과 1.34는 자본 문턱 2.95와 기존 천장 2.94에 크게 미달 — 지식 가치는 있으나 투자 후보 아님")),
      list(type = "table", emoji = "📊", heading = "가중 규칙별 실측 (canonical PORT_t, cap-w)",
           df = data.frame(
             규칙 = c("등가중(base)", "고정 가족균등", "정보계수 비례", "★실현성과 정렬", "역분산"),
             PORT_t = sprintf("%.2f", TAB[match(c("base","W_famfix","W_icir","W_portt","W_ivar"), model), port_t_capwt]),
             "paired_t" = c("-", "-0.97", "+0.89", "+2.57", "-0.01"))),
      list(type = "bullet", emoji = "🚩", heading = "주의",
           items = c("graduation 3종 전부 미달 (PORT_t 1.34 / 검증구간 유지율 -0.41 / Calmar 0.40)",
                     "2015~2019 정보계수 침하 0.018 — 부기간 불안정",
                     "lag-1 스트레스 통과(2.57→2.48) — 미래참조 누출 반증 완료")),
      list(type = "bullet", emoji = "➡️", heading = "다음",
           items = c("판정: 기전 양성 + config-scoped negative(천장 미달) — 선별이 지배적 carrier 재확인",
                     "next_probe: PORT_t-정렬 가중 x 비-return 패널(insider) / 챔피언(선별-정렬) 위 재적용은 R10 null로 제외",
                     "Q-Lead 수신 후 Ledger 적립 + risk 단계 전이 여부 판단"))),
    charts = c(p1, p2))
  TRUE
}, error = function(e){ cat("TG FAIL:", conditionMessage(e), "\n"); FALSE })
cat(sprintf("telegram=%s\nBUILD_DONE\n", tg_ok))
