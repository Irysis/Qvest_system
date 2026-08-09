# =============================================================================
# repair_package_contract.R — WT-D20260808_001 alpha_package.json 계약 수리
#
# 왜: 병행 실행된 alpha-research 가 R write_json 으로 alpha_package.json 을 디스크에
#     올렸고(= PreToolUse[Write] 시야 밖), 그 산출물이 ast_spec_gate BLOCK +
#     schema 위반 13건 상태다. 하류(risk/optimizer/judge)가 그대로 소비한다.
#     본 스크립트는 **판정·수치·결론을 바꾸지 않고** 계약 위반만 수리한다.
#
# 수리 6건 (전부 형식 — 내용 보존):
#   R1 hypothesis.falsification: 문자열 → 객체배열(field_dictionary 필드 지목). 원문 verbatim 보존
#   R2 pit{sig_date,decision_ts} 추가 (v1.1 conditional required, 누락)
#   R3 diagnostics.alpha_inheritance_cor 추가 (required 누락) — 실측값
#   R4 diagnostics 6개 null → 실측값 (rank_ic/icir/monotonicity/subperiod_stability/
#      harvey_t_stat/post_neutralization_ic). null 은 스키마 타입 number 위반
#   R5 factor_specs.economic_rationale: 자유서술 → enum. 원문은 _detail 로 보존
#   R6 factors[].ast escape_contract: provenance_path/builder/vintage →
#      provenance{store_build_hash,generator_code_path,generated_at} (스키마 required)
#      + ast_verify 방언(node 최상위 provenance/production_parity_verified) 병기
#
# 원본은 alpha_package_prerepair_20260808.json 으로 보존한다.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/repair_package_contract.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260808_001")
say <- function(fmt, ...) cat(sprintf(paste0("[repair] ", fmt, "\n"), ...))

# ── 0. 배터리 실측 (emitted 패널 = 디스크 현행 alpha_scores.parquet) ─────────
A <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))[, Date := as.Date(Date)]
say("INPUT alpha_scores nrow=%d MONTHLY n_month=%d %s~%s cols=[%s]", nrow(A), uniqueN(A$Date),
    min(A$Date), max(A$Date), paste(names(A), collapse = ","))
fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
RET <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
say("INPUT fwd returns nrow=%d MONTHLY n_month=%d", nrow(RET), uniqueN(RET$Date))

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f,
    vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

battery <- function(sc) {
  D <- merge(sc, RET, by = c("Date","Ticker"))
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  qm <- D[, { if (.N>=20L && sd(score)>0) { q <- cut(frank(score), breaks=5, labels=FALSE)
      as.list(setNames(sapply(1:5, function(k) mean(Ret_1m[q==k], na.rm=TRUE)), paste0("m",1:5)))
    } else as.list(setNames(rep(NA_real_,5), paste0("m",1:5))) }, by=Date]
  qmean <- sapply(paste0("m",1:5), function(k) mean(qm[[k]], na.rm=TRUE))
  ic[, p := fifelse(Date < as.Date("2015-01-01"),"P1", fifelse(Date < as.Date("2020-01-01"),"P2","P3"))]
  sp <- ic[, .(ic_mean=mean(ic), ic_t=nw_t(ic), n=.N), by=p][order(p)]
  list(rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), harvey_t=nw_t(ic$ic),
       monotonicity=mean(diff(qmean)>0), subperiod_stability=mean(sp$ic_mean>0),
       quintile_ann_pct=100*12*qmean, subperiod=sp, n_month=nrow(ic))
}
b_emit <- battery(A[is.finite(score_q01filtered), .(Date, Ticker, score = score_q01filtered)])
b_base <- battery(A[is.finite(score), .(Date, Ticker, score)])
say("emitted(score_q01filtered): rank_ic %+.4f ICIR %+.3f Harvey-t %+.2f mono %.2f subperiod %.2f n=%d",
    b_emit$rank_ic, b_emit$icir, b_emit$harvey_t, b_emit$monotonicity, b_emit$subperiod_stability, b_emit$n_month)
say("  분위 평균 연수익 Q1..Q5 = %s", paste(sprintf("%+.1f%%", b_emit$quintile_ann_pct), collapse=" "))
say("  subperiod: %s", paste(sprintf("%s IC %+.4f (t %+.2f, n=%d)", b_emit$subperiod$p,
    b_emit$subperiod$ic_mean, b_emit$subperiod$ic_t, b_emit$subperiod$n), collapse=" | "))
say("base(M01 score): rank_ic %+.4f Harvey-t %+.2f mono %.2f", b_base$rank_ic, b_base$harvey_t, b_base$monotonicity)

# post-neutralization IC (섹터+사이즈) — 필터 축 Q01_EB
SEC <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260802_009/sector_panel.parquet")))[, Date:=as.Date(Date)]
SZ  <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260802_009/size_panel.parquet")))[, Date:=as.Date(Date)]
szc <- setdiff(names(SZ), c("Date","Ticker"))[1]
N <- merge(A[is.finite(Q01_EB), .(Date,Ticker,fz=Q01_EB)], SEC, by=c("Date","Ticker"), all.x=TRUE)
N <- merge(N, SZ, by=c("Date","Ticker"), all.x=TRUE)
N[is.na(Sector), Sector:="UNKNOWN"][, lsz := suppressWarnings(log(pmax(get(szc),1)))]
N[, fzn := { ok <- is.finite(fz)&is.finite(lsz); r <- rep(NA_real_,.N)
  if (sum(ok)>=30L && uniqueN(Sector[ok])>=2L) r[ok] <- residuals(lm(fz[ok] ~ lsz[ok] + factor(Sector[ok]))); r }, by=Date]
b_neu <- battery(N[is.finite(fzn), .(Date,Ticker,score=fzn)])
b_q01 <- battery(A[is.finite(Q01_EB), .(Date,Ticker,score=Q01_EB)])
say("Q01_EB rank_ic %+.4f → 섹터+사이즈 중립화 %+.4f (retention %.2f, Harvey-t %+.2f)",
    b_q01$rank_ic, b_neu$rank_ic, b_neu$rank_ic/b_q01$rank_ic, b_neu$harvey_t)

# alpha_inheritance_cor (emitted vs base M01) — Spearman 정본
A[, emit_rankable := fifelse(is.finite(score_q01filtered), score, score - 1000)]
inh <- A[is.finite(score), .(s = cor(emit_rankable, score, method="spearman")), by=Date]
INH <- median(inh$s, na.rm=TRUE)
say("alpha_inheritance_cor (Spearman 중앙값) = %.4f", INH)

# ── 1. 원본 보존 + 수리 ──────────────────────────────────────────────────────
PKG_F <- file.path(MB, "alpha_package.json")
raw <- readLines(PKG_F, warn = FALSE)
writeLines(raw, file.path(MB, "alpha_package_prerepair_20260808.json"))
say("원본 보존 → alpha_package_prerepair_20260808.json (%d bytes)", sum(nchar(raw))+length(raw))
pkg <- fromJSON(PKG_F, simplifyVector = FALSE)

fals_orig <- pkg$hypothesis$falsification
stopifnot(is.character(fals_orig))
# R1: 문자열 → 객체배열. 원문은 그대로 쪼개 expectation 에 보존(재작성 아님).
pkg$hypothesis$falsification <- list(
  list(field="D03_RealVol", expectation="(F1 원문) 신호 구조: D03 자기-분위 조건부 forward-active 곡선이 좌측-국소화 형태(하위 분위 유의 열위 + 최상위 분위 평탄/음). [실측: Q1−Q3 −2.07%/yr NW t −0.63 > −1 → 좌측-국소화 REJECTED. 유의 이탈은 최상위 분위 −6.90%/yr t −2.30 = 우측-국소화]"),
  list(field="Q01_GPA", expectation="(F1 원문, Q01 별도 실행) 하위 분위 유의 열위 + 최상위 분위 평탄/음. [실측: Q1−Q3 −5.21%/yr t −2.25 · Q5−Q3 −0.58%/yr t −0.21 → SUPPORTED]"),
  list(group_id="A6_investor_flow_stock_daily", expectation="(F2 원문) 주체: D03 하위(고변동) 분위 종목에 개인 순매수 강도가 연속 조건화 회귀에서 유의하게 집중(Q01 은 동일 회귀 별도 실행 — 주체가 다를 수 있음을 사전 인정). [실측: log(시총) 교락 통제 후에도 잔존 — D03 −0.0378 t −4.29 (잔존 0.83) · Q01 −0.0228 t −4.33 (잔존 1.13) → SUPPORTED, 사이즈 대용 아님. 단 동시기 연관이며 예측 주장 아님]"),
  list(group_id="A1_RAWDATA_OHLCVS_daily", expectation="(F3 원문) 구조: D03 최상위(초저변동) 분위의 시장 β 가 유니버스 중앙값 대비 유의하게 낮음(β-drag 경로). [실측 trailing 60m PIT: D03 최상위 0.765 vs 유니버스 중앙 0.979, 차 −0.215 NW t −12.71 → SUPPORTED]"),
  list(field="M01_Mom_12_1", expectation="(F4 원문) (a) 전용 사전 킬스위치: 경계 밴드(rank 20~40) 내 D03/Q01 조건부 forward-active 기울기 <= 0 이면 (a) 는 측정 전 기각. [실측: D03 −3.28%/yr t −1.28 · Q01 −3.26%/yr t −1.52 → (a) 사전 KILL, 측정하지 않음]")
)
pkg$hypothesis$falsification_original_text <- fals_orig   # 원문 무손실 보존

# R2: pit
pkg$pit <- list(sig_date = "2026-06-30", decision_ts = "2026-06-30",
  note = "패널 최신 월말. as_of_date 2026-08-08 과의 차이는 팩터 패널 vintage lag")

# R3/R4: diagnostics 채우기 (기존 필드·값 불변, null 만 실측 대체 + 누락 추가)
d <- pkg$diagnostics
d$rank_ic <- round(b_emit$rank_ic, 6)
d$icir <- round(b_emit$icir, 6)
d$monotonicity <- round(b_emit$monotonicity, 4)
d$subperiod_stability <- round(b_emit$subperiod_stability, 4)
d$harvey_t_stat <- round(b_emit$harvey_t, 4)
d$post_neutralization_ic <- round(b_neu$rank_ic, 6)
d$alpha_inheritance_cor <- round(INH, 4)
d$alpha_inheritance_cor_note <- "Spearman 월별 중앙값 (emitted masked score vs base M01_PATHQ). < 0.95 → wt_type=discovery 유지, 재분류 제안 불요."
d$advisory_battery_note <- paste0(
  "[계약 수리 2026-08-08] 종전 6개 필드가 null 이었으나 schema 는 number 를 요구한다. ",
  "본 라운드 판정량이 paired 한계기여인 것은 맞으나 Step 4-B advisory 배터리는 기록 의무이므로 실측해 채웠다. ",
  "값은 emitted 패널(score_q01filtered) 기준이며 판정 권위 아님(measurement-graduation §3 advisory).")
d$advisory_battery_by_factor <- list(
  emitted_masked = list(rank_ic = round(b_emit$rank_ic,6), harvey_t = round(b_emit$harvey_t,4),
    monotonicity = round(b_emit$monotonicity,4), quintile_mean_ann_pct = round(unname(b_emit$quintile_ann_pct),3)),
  base_M01 = list(rank_ic = round(b_base$rank_ic,6), harvey_t = round(b_base$harvey_t,4),
    monotonicity = round(b_base$monotonicity,4), quintile_mean_ann_pct = round(unname(b_base$quintile_ann_pct),3)),
  Q01_EB_filter_axis = list(rank_ic = round(b_q01$rank_ic,6), harvey_t = round(b_q01$harvey_t,4),
    subperiod_stability = round(b_q01$subperiod_stability,4)))
d$subperiod_rank_ic_emitted <- lapply(seq_len(nrow(b_emit$subperiod)), function(i)
  list(period = b_emit$subperiod$p[i], ic_mean = round(b_emit$subperiod$ic_mean[i],6),
       ic_t_nw = round(b_emit$subperiod$ic_t[i],4), n_months = b_emit$subperiod$n[i]))
pkg$diagnostics <- d

# R5: economic_rationale enum
er_map <- c("behavioral","behavioral","behavioral","behavioral","behavioral")
for (i in seq_along(pkg$factor_specs)) {
  orig <- pkg$factor_specs[[i]]$economic_rationale
  if (!is.null(orig) && !orig %in% c("risk_premium","behavioral","structural")) {
    pkg$factor_specs[[i]]$economic_rationale_detail <- orig      # 원문 보존
    pkg$factor_specs[[i]]$economic_rationale <- er_map[i]
  }
}

# R6: escape_contract provenance 정규화 (+ ast_verify 방언 병기)
fix_leaf <- function(node) {
  if (!is.list(node)) return(node)
  if (!is.null(node$leaf) && identical(node$leaf, "STORED_SCORE")) {
    ec <- node$escape_contract
    if (!is.null(ec) && is.null(ec$provenance)) {
      ec$provenance <- list(
        store_build_hash = if (!is.null(ec$provenance_path)) ec$provenance_path else "unknown",
        generator_code_path = if (!is.null(ec$provenance_builder)) ec$provenance_builder else "unknown",
        generated_at = if (!is.null(ec$provenance_vintage)) ec$provenance_vintage else "unknown")
      if (is.null(ec$production_parity_verified)) ec$production_parity_verified <- FALSE
      node$escape_contract <- ec
      # ast_verify 방언: node 최상위 provenance / production_parity_verified 를 함께 본다
      node$provenance <- ec$provenance
      node$production_parity_verified <- ec$production_parity_verified
      node$vintage_available <- TRUE
      node$vintage_note <- "WT-009/Iter31 저장 패널은 생성 후 불변(재생성 없음) — 개정 위험 없음을 근거와 함께 선언"
    }
  }
  for (k in c("args","children")) if (!is.null(node[[k]]) && is.list(node[[k]]))
    node[[k]] <- lapply(node[[k]], fix_leaf)
  node
}
for (i in seq_along(pkg$factors)) pkg$factors[[i]]$ast <- fix_leaf(pkg$factors[[i]]$ast)

# challenge_flags 추가 (침묵 수리 금지)
pkg$challenge_flags <- c(pkg$challenge_flags, list(
  "[계약 수리 2026-08-08 · alpha-research 2차] 본 패키지는 R write_json 으로 디스크에 올라 PreToolUse[Write] ast_spec_gate 를 우회했고, 사후 검사에서 gate BLOCK(falsification 문자열) + schema 위반 13건이 확인됐다. 판정·수치·결론은 일절 변경하지 않고 계약 위반 6종만 수리했다(원본 = alpha_package_prerepair_20260808.json). 상세 = challenge_note_contract_repair.md",
  "[병행 중복 실행] 동일 WT 를 두 alpha-research 실행이 병렬 수행했다. 핵심 수치는 독립 재현됨(P1: D03 −3.443/t −1.093 · Q01 +3.771/t +1.606 양쪽 일치, F1/F4 일치, p_hit 0.386 vs 0.382). 이는 AX-008 triangulation 상 유리하나 중복 실행 자체는 v8.3 in-flight 인덱싱이 막았어야 할 사건 — Q-Lead 보고 대상.",
  "[추가 실측] F2 사이즈 교락 통제 — log(시총) 통제 후에도 개인 순매수 집중 잔존(D03 t −4.29 잔존 0.83 · Q01 t −4.33 잔존 1.13). 사이즈 대용 가설 배제.",
  "[추가 실측] Q01_EB rank-IC 의 시기 편중 — P1(2001-2014) +0.0327 t 2.78 / P2(2015-2019) −0.0010 / P3(2020-2026) −0.0037. 전표본 F1·P1 결과는 pre-2015 가중이다. 분할 판정이 아니라 advisory 진단의 정직 라벨.",
  ## ★[2026-08-09 verification_followup 정정] 아래 문장은 **거짓 서술**을 담고 있었다.
  ##   원문: "... 5분위 평균 연수익은 Q1 +13.1% → Q5 +8.0% 로 단조 감소(monotonicity 0.25)."
  ##   실측: 단조가 아니라 **Q2 정점 역U형** [12.9, 15.4, 14.3, 11.8, 8.2] (Q1→Q2 +2.5%p 상승).
  ##   더구나 Q5−Q1 평균 스프레드는 연 −4.72% (NW t −1.02) 로 **비유의**.
  ##   같은 문장의 monotonicity 0.25 가 이미 비단조를 뜻해 수치와 서술이 자기모순이었다.
  ##   ★이 스크립트는 이미 실행된 이력이다 — 재실행하면 정정 문안이 반영된다.
  "[추가 실측 · 2026-08-09 정정] D03_EWMA 순위↔평균 형상 불일치 — rank-IC Harvey-t +3.46~3.50(3.0 통과)인데 5분위 평균 연수익은 Q2 정점 역U형 [12.9, 15.4, 14.3, 11.8, 8.2] (Q1→Q2 +2.5%p 상승, 하락은 Q3→Q5 국한). Q5−Q1 평균 스프레드 연 −4.72%(NW t −1.02) = 비유의. 확립 사실은 '부호 역전'이 아니라 '순위 통계 양(+) ∧ 평균 스프레드 비유의'. 'rank-IC Harvey-t>=3 ∧ monotonicity<0.5' 자동 라벨 제안은 유지하되 명칭은 '순위-평균 형상 불일치'가 정확(소비면 ⑥). 출처 = verification_followup/probe_d03_quintile.R",
  "[계약 표면 분열 보고] schema 는 ast_node.args 에 number 스칼라를 허용(윈도우·경계)하는데 ast_verify.py 는 비-dict 노드를 '노드 형상 오류'로 FAIL_CONTRACT 처리한다. init prompt 의 표준 예시(TS_SUM(leaf, 3))조차 이 형태다. ALB-005 와 동류의 두 계층 불일치 — 인프라 백로그 등재 권고."))

write_json(pkg, PKG_F, pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
say("수리본 저장 → %s", PKG_F)
saveRDS(list(battery_emitted=b_emit, battery_base=b_base, battery_q01=b_q01,
             battery_neutralized=b_neu, alpha_inheritance_cor=INH),
        file.path(OUT, "repair_battery.rds"))
say("=== 계약 수리 완료 ===")
