# =============================================================================
# run_fu_task4_emit_repair.R — ④ 발행 패널 유동성 수리 + advisory 배터리 재산출
#
# 결함(PANEL_DEFECT_20260809_WT001_LIQUIDITY): run_fq122_emit.R 이 사전등록 고정 축
#   adv>=2e8 을 적용하지 않고 패널을 발행했다(미달 2,875행 = 3.31%).
#
# ★basis 실측 결과 유동성 자가 둘이다 —
#   (A) 계약 liq_dt: build_monthly_forward_returns() 의 adv = **Vol0*Close0**
#       (= 월말 당일 거래대금 1일치. 주석은 "20d ADV"라 적혀 있으나 코드는 1일치다)
#   (B) 고지문 검증 절차: rawdata frollmean(Vol*Close, 20) 월말값 (= Production
#       Constraints 의 "20일 평균 거래대금" 정의)
#   두 자는 상관 0.929 · 판정 불일치 2,305행(2.61%) 로 **다른 양**이다.
#   ⇒ 한 자만 쓰면 생성기와 검사기가 어긋난다(08-08 상한 0.20 사건 계통).
#   ⇒ 발행 패널은 **두 자를 모두 통과한 행(교집합)** 으로 하고 두 adv 를 컬럼으로 동봉,
#     basis 를 선언 필드로 못 박는다. (A) 만 쓰던 판정 유니버스의 부분집합이므로
#     판정 대비 느슨해지는 방향이 아니다.
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/verification_followup/run_fu_task4_emit_repair.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(f,...) cat(sprintf(paste0("[fu4] ",f,"\n"),...))
LIQ_MIN <- 2e8

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f,
    vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

# ── 검사기 (생성기와 분리 — 같은 함수로 수리판·위반주입판을 모두 검사한다) ──
#' @return list(n, n_fail_A, n_fail_B, n_na_A, n_na_B, verdict)
check_liquidity_axis <- function(panel, advA, advB, liq_min = LIQ_MIN) {
  P <- copy(panel)[, ym := format(Date, "%Y-%m")]
  P <- merge(P, advA, by = c("Date","Ticker"), all.x = TRUE)
  P <- merge(P, advB, by = c("Ticker","ym"), all.x = TRUE)
  fA <- sum(P$adv_contract < liq_min, na.rm = TRUE); fB <- sum(P$adv20_raw < liq_min, na.rm = TRUE)
  nA <- sum(is.na(P$adv_contract)); nB <- sum(is.na(P$adv20_raw))
  list(n = nrow(P), n_fail_contract = fA, n_fail_raw20 = fB,
       share_fail_raw20 = fB/nrow(P), n_na_contract = nA, n_na_raw20 = nB,
       verdict = if (fA == 0 && fB == 0 && nA == 0 && nB == 0) "CLEAN" else "VIOLATION")
}

# ── 0. 입력 실측 ─────────────────────────────────────────────────────────────
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT tuned_panel nrow=%d n_month=%d %s~%s", nrow(TUNED), uniqueN(TUNED$Date), min(TUNED$Date), max(TUNED$Date))
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select = c("Date","Ticker","Close","Vol","K200","KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d DAILY n_day=%d %s~%s", nrow(R), uniqueN(R$Date), min(R$Date), max(R$Date))
setorder(R, Ticker, Date)
R[, adv20 := frollmean(Vol*Close, n = 20L, align = "right"), by = Ticker]
R[, ym := format(Date, "%Y-%m")]
ADV_B <- R[, .(adv20_raw = last(adv20)), by = .(Ticker, ym)]           # (B) 20일 평균
MEND <- sort(R[, .(Date = max(Date)), by = ym]$Date)
UNIV <- R[Date %in% MEND & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
rm(R); gc(verbose = FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
ADV_A <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv_contract = adv)]  # (A) 계약
RET <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
say("adv 자 A(계약 Vol0*Close0) %d행 · B(rawdata 20d) %d행", nrow(ADV_A), nrow(ADV_B))

# ── 1. 구 패널 검사 → superseded 이동 ────────────────────────────────────────
OLD_F <- file.path(OUT, "alpha_scores.parquet")
OLD <- as.data.table(read_parquet(OLD_F))[, Date := as.Date(Date)]
say("=== 1. 구 발행 패널 검사 (결함 재현) ===")
c_old <- check_liquidity_axis(OLD[, .(Date, Ticker)], ADV_A, ADV_B)
say("  구 패널 %d행 → 자B 미달 %d행 (%.2f%%) · 자A 미달 %d행 · 판정 %s",
    c_old$n, c_old$n_fail_raw20, 100*c_old$share_fail_raw20, c_old$n_fail_contract, c_old$verdict)
say("  ★고지문 독립 재측정(2,875행 / 3.31%%)과 대조 — 일치 여부: %s",
    if (abs(c_old$n_fail_raw20 - 2875) <= 5) "일치" else sprintf("불일치(본 측정 %d행) — 절차 차이 조사 필요", c_old$n_fail_raw20))
SUP_F <- file.path(OUT, "alpha_scores_superseded_20260809.parquet")
write_parquet(OLD, SUP_F)
say("  구 패널 보존 → alpha_scores_superseded_20260809.parquet (병존 금지 규약: 정본명은 재발행판이 차지)")

# ── 2. 재발행 (eligible_set 정의 적용) ───────────────────────────────────────
say("=== 2. 재발행 — eligible_set(adv>=2e8, 두 자 교집합) 적용 ===")
W <- dcast(TUNED[Factor_Name %in% c("M01_PATHQ","D03_EWMA","Q01_EB")],
           Date + Ticker ~ Factor_Name, value.var = "score")
W <- merge(W, UNIV, by = c("Date","Ticker"))
S <- W[is.finite(M01_PATHQ)]
say("  유니버스 적용 후 %d행 (= 구 발행 패널 %d행 재현: %s)", nrow(S), nrow(OLD),
    if (nrow(S) == nrow(OLD)) "일치" else "★불일치")
S[, ym := format(Date, "%Y-%m")]
S <- merge(S, ADV_A, by = c("Date","Ticker"), all.x = TRUE)
S <- merge(S, ADV_B, by = c("Ticker","ym"), all.x = TRUE)
n_pre <- nrow(S)
S <- S[is.finite(adv_contract) & adv_contract >= LIQ_MIN &
       is.finite(adv20_raw)   & adv20_raw   >= LIQ_MIN]
say("  유동성 축 적용: %d행 → %d행 (제거 %d행 · %.2f%%)", n_pre, nrow(S), n_pre-nrow(S),
    100*(n_pre-nrow(S))/n_pre)
S[, ym := NULL]
S[, rk_m01 := frank(-M01_PATHQ, ties.method = "first"), by = Date]
for (f in c("D03_EWMA","Q01_EB"))
  S[, (paste0(f,"_pct")) := { v <- get(f); r <- rep(NA_real_, .N); ok <- is.finite(v)
      if (any(ok)) r[ok] <- frank(v[ok])/sum(ok); r }, by = Date]
S[, excl_q01_q20 := is.finite(Q01_EB_pct) & Q01_EB_pct <= 0.20]
S[, excl_d03_q20 := is.finite(D03_EWMA_pct) & D03_EWMA_pct <= 0.20]
S[, score := M01_PATHQ]
S[, score_q01filtered := ifelse(excl_q01_q20, NA_real_, M01_PATHQ)]
S[, universe_basis := "adv_contract(Vol0*Close0) >= 2e8 AND adv20_raw(frollmean 20d) >= 2e8"]
write_parquet(S, OLD_F)
say("  재발행 완료: %d행 · %d월 · 제외율 Q01 %.4f / D03 %.4f",
    nrow(S), uniqueN(S$Date), mean(S$excl_q01_q20), mean(S$excl_d03_q20))

# ── 3. 검증 + 위반 주입 ──────────────────────────────────────────────────────
say("=== 3. 검증 (재발행판) + 위반 주입 (필터 제거판) ===")
c_new <- check_liquidity_axis(S[, .(Date, Ticker)], ADV_A, ADV_B)
say("  [재발행판] %d행 · 자A 미달 %d · 자B 미달 %d · 결측 %d/%d → **%s**",
    c_new$n, c_new$n_fail_contract, c_new$n_fail_raw20, c_new$n_na_contract, c_new$n_na_raw20, c_new$verdict)
INJ <- W[is.finite(M01_PATHQ), .(Date, Ticker)]                 # 필터 제거판 = 위반 주입
c_inj <- check_liquidity_axis(INJ, ADV_A, ADV_B)
say("  [위반 주입판] %d행 · 자A 미달 %d · 자B 미달 %d → **%s**",
    c_inj$n, c_inj$n_fail_contract, c_inj$n_fail_raw20, c_inj$verdict)
inj_ok <- identical(c_new$verdict,"CLEAN") && identical(c_inj$verdict,"VIOLATION")
say("  ★검사 실효: 수리판 CLEAN ∧ 주입판 VIOLATION = %s", if (inj_ok) "PASS (검사기 살아있음)" else "FAIL")
if (!inj_ok) stop("위반 주입 테스트 실패 — 검사기가 죽었거나 수리가 불완전하다. 여기서 멈춘다.")

# ── 4. advisory 배터리 재산출 (재발행 패널 기준, 계약과 동일 함수) ───────────
say("=== 4. advisory 배터리 재산출 ===")
battery <- function(sc) {
  D <- merge(sc, RET, by = c("Date","Ticker"))
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  qm <- D[, { if (.N>=20L && sd(score)>0) { q <- cut(frank(score), breaks=5, labels=FALSE)
      as.list(setNames(sapply(1:5, function(k) mean(Ret_1m[q==k], na.rm=TRUE)), paste0("m",1:5)))
    } else as.list(setNames(rep(NA_real_,5), paste0("m",1:5))) }, by=Date]
  qmean <- sapply(paste0("m",1:5), function(k) mean(qm[[k]], na.rm=TRUE))
  ic[, p := fifelse(Date < as.Date("2015-01-01"),"P1", fifelse(Date < as.Date("2020-01-01"),"P2","P3"))]
  spp <- ic[, .(ic_mean=mean(ic), ic_t=nw_t(ic), n=.N), by=p][order(p)]
  list(rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), harvey_t=nw_t(ic$ic),
       monotonicity=mean(diff(qmean)>0), subperiod_stability=mean(spp$ic_mean>0),
       quintile_ann_pct=100*12*qmean, subperiod=spp, n_month=nrow(ic))
}
b_emit <- battery(S[is.finite(score_q01filtered), .(Date,Ticker,score=score_q01filtered)])
b_base <- battery(S[is.finite(score), .(Date,Ticker,score)])
b_q01  <- battery(S[is.finite(Q01_EB), .(Date,Ticker,score=Q01_EB)])
b_d03  <- battery(S[is.finite(D03_EWMA), .(Date,Ticker,score=D03_EWMA)])
say("  emitted: rank_ic %+.6f ICIR %+.4f Harvey-t %+.4f mono %.2f subp %.4f n=%d",
    b_emit$rank_ic, b_emit$icir, b_emit$harvey_t, b_emit$monotonicity, b_emit$subperiod_stability, b_emit$n_month)
say("    분위 연수익 Q1..Q5 = %s", paste(sprintf("%+.2f%%", b_emit$quintile_ann_pct), collapse=" "))
say("  base_M01: rank_ic %+.6f Harvey-t %+.4f mono %.2f", b_base$rank_ic, b_base$harvey_t, b_base$monotonicity)
say("  Q01_EB  : rank_ic %+.6f Harvey-t %+.4f subp %.4f", b_q01$rank_ic, b_q01$harvey_t, b_q01$subperiod_stability)
say("  D03_EWMA: rank_ic %+.6f Harvey-t %+.4f mono %.2f", b_d03$rank_ic, b_d03$harvey_t, b_d03$monotonicity)

# post-neutralization IC (섹터+사이즈) — 계약 수리본과 동일 절차
SEC <- as.data.table(read_parquet(file.path(IN9,"sector_panel.parquet")))[, Date:=as.Date(Date)]
SZ  <- as.data.table(read_parquet(file.path(IN9,"size_panel.parquet")))[, Date:=as.Date(Date)]
szc <- setdiff(names(SZ), c("Date","Ticker"))[1]
N <- merge(S[is.finite(Q01_EB), .(Date,Ticker,fz=Q01_EB)], SEC, by=c("Date","Ticker"), all.x=TRUE)
N <- merge(N, SZ, by=c("Date","Ticker"), all.x=TRUE)
N[is.na(Sector), Sector:="UNKNOWN"][, lsz := suppressWarnings(log(pmax(get(szc),1)))]
N[, fzn := { ok <- is.finite(fz)&is.finite(lsz); r <- rep(NA_real_,.N)
  if (sum(ok)>=30L && uniqueN(Sector[ok])>=2L) r[ok] <- residuals(lm(fz[ok] ~ lsz[ok] + factor(Sector[ok]))); r }, by=Date]
b_neu <- battery(N[is.finite(fzn), .(Date,Ticker,score=fzn)])
say("  post-neutralization IC (Q01축) %+.6f (retention %.3f · Harvey-t %+.4f)",
    b_neu$rank_ic, b_neu$rank_ic/b_q01$rank_ic, b_neu$harvey_t)

S[, emit_rankable := fifelse(is.finite(score_q01filtered), score, score - 1000)]
INH <- median(S[is.finite(score), .(s = cor(emit_rankable, score, method="spearman")), by=Date]$s, na.rm=TRUE)
S[, emit_rankable := NULL]
say("  alpha_inheritance_cor (Spearman 중앙값) = %.4f", INH)

# ── 5. alpha_vector / confidence_vector 기계 파생 ────────────────────────────
say("=== 5. alpha_vector 재파생 (손코딩 금지) ===")
last_d <- max(S$Date)
L <- S[Date == last_d & !is.na(score_q01filtered)][order(-score_q01filtered)][1:25]
alpha_vec <- as.list(setNames(round(L$score_q01filtered, 6), L$Ticker))
conf <- 0.35 + 0.15*(is.finite(L$D03_EWMA) & is.finite(L$Q01_EB)) + 0.10*(L$rk_m01 <= 15)
conf_vec <- as.list(setNames(round(pmin(pmax(conf,0),1),3), L$Ticker))
say("  최신월 %s · %d종목 · adv20 최소 %.3e (2e8 대비 %.1f배)",
    as.character(last_d), length(alpha_vec), min(L$adv20_raw), min(L$adv20_raw)/2e8)
OLDPKG <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json"), simplifyVector=FALSE)
old_tk <- names(OLDPKG$alpha_vector); new_tk <- names(alpha_vec)
say("  구 벡터 대비 변경: 유지 %d · 신규 %d · 이탈 %d",
    length(intersect(old_tk,new_tk)), length(setdiff(new_tk,old_tk)), length(setdiff(old_tk,new_tk)))
if (length(setdiff(new_tk, old_tk))) say("  신규: %s", paste(setdiff(new_tk,old_tk), collapse=" "))
if (length(setdiff(old_tk, new_tk))) say("  이탈: %s", paste(setdiff(old_tk,new_tk), collapse=" "))

saveRDS(list(check_old=c_old, check_new=c_new, check_injected=c_inj, injection_test_pass=inj_ok,
  rows_old=nrow(OLD), rows_new=nrow(S), months_new=uniqueN(S$Date),
  excl_rate_q01=mean(S$excl_q01_q20), excl_rate_d03=mean(S$excl_d03_q20),
  battery_emitted=b_emit, battery_base=b_base, battery_q01=b_q01, battery_d03=b_d03,
  battery_neutralized=b_neu, alpha_inheritance_cor=INH,
  alpha_vector=alpha_vec, confidence_vector=conf_vec, last_date=as.character(last_d),
  vec_kept=intersect(old_tk,new_tk), vec_added=setdiff(new_tk,old_tk), vec_dropped=setdiff(old_tk,new_tk),
  universe_basis="adv_contract(Vol0*Close0) >= 2e8 AND adv20_raw(frollmean 20d) >= 2e8"),
  file.path(FU,"fu_task4_results.rds"))
say("=== ④ 완료 → verification_followup/fu_task4_results.rds ===")
