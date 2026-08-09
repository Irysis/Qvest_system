## A3 — 층 1/2/3 구성 + PIT offset 스캔 + F2/primary(β_s 부호) 검정
## 사전등록: stage_artifacts/WT-D20260809_004/preregistration.json (본 스크립트 실행 전 작성)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A3] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
P <- readRDS(file.path(OUT, "panels.rds"))
ELIG <- P$ELIG; FAC <- P$FAC; RET <- P$fwd$returns_dt; BEN <- P$fwd$bench_dt; ST <- P$sig_tbl

## ── 0. 입력 실측 (형태 가정 금지) ───────────────────────────────────────────
say("ELIG %s행/%d월 · FAC %s행/%d월 · RET %s행/%d월 · sig_tbl %d행",
    format(nrow(ELIG),big.mark=","), uniqueN(ELIG$Date),
    format(nrow(FAC),big.mark=","), uniqueN(FAC$sig_date),
    format(nrow(RET),big.mark=","), uniqueN(RET$Date), nrow(ST))

## ── 1. 성장 합성 스코어 (3종 동일가중 z 평균) ───────────────────────────────
GW <- dcast(FAC, sig_date + Ticker ~ Factor_Name, value.var = "z")
gcols <- c("C01_SUE","C02_EPS_Chg_1m","M26_Revenue_Mom")
GW[, n_ok := Reduce(`+`, lapply(gcols, function(c0) as.integer(!is.na(GW[[c0]]))))]
GW[, growth := rowMeans(.SD, na.rm = TRUE), .SDcols = gcols]
GW[n_ok == 0L, growth := NA_real_]
say("성장 스코어: %s행 · 3종 전부 보유 %.1f%% · 1종 이상 %.1f%%",
    format(nrow(GW),big.mark=","), 100*mean(GW$n_ok==3L), 100*mean(GW$n_ok>=1L))

## 3종 pairwise 횡단면 상관 (중복 진단 — Factor Zoo 축소 의무)
pw <- GW[, {
  cc <- suppressWarnings(cor(.SD, use = "pairwise.complete.obs", method = "spearman"))
  .(p12 = cc[1,2], p13 = cc[1,3], p23 = cc[2,3])
}, by = sig_date, .SDcols = gcols]
say("pairwise Spearman 월평균: C01~C02 %.3f · C01~M26 %.3f · C02~M26 %.3f",
    mean(pw$p12, na.rm=TRUE), mean(pw$p13, na.rm=TRUE), mean(pw$p23, na.rm=TRUE))

## 자격 유니버스로 제한
SC <- merge(ELIG[, .(sig_date = Date, Ticker, Sector)], GW[, .(sig_date, Ticker, growth, n_ok)],
            by = c("sig_date","Ticker"), all.x = TRUE)
say("자격패널 성장 커버리지 %.1f%% (결측 %d행)", 100*mean(!is.na(SC$growth)), sum(is.na(SC$growth)))
SC <- SC[!is.na(growth)]

## ── 2. ★PIT offset 스캔 — 동시성 오염 실증 (FQ-165 계통) ────────────────────
##   offset+1 = 우리 컨벤션 (sig_date 스코어 → 다음달 실현수익)
##   offset 0 = sig_date 스코어 → **직전 달** 실현수익 (동시성). RET 의 Date 는 신호일이므로
##              직전 sig_date 의 Ret_1m 이 sig_date 로 끝나는 달의 수익이다.
sd_all <- sort(unique(RET$Date))
prevmap <- data.table(sig_date = sd_all[-1], prev_sig = sd_all[-length(sd_all)])
R1 <- RET[, .(sig_date = Date, Ticker, ret_fwd = Ret_1m)]                        # offset +1
R0 <- merge(prevmap, RET[, .(prev_sig = Date, Ticker, ret_cur = Ret_1m)], by = "prev_sig",
            allow.cartesian = TRUE)[, .(sig_date, Ticker, ret_cur)]              # offset 0
IC <- merge(SC[, .(sig_date, Ticker, growth)], R1, by = c("sig_date","Ticker"))
IC <- merge(IC, R0, by = c("sig_date","Ticker"), all.x = TRUE)
ics <- IC[, .(ic1 = suppressWarnings(cor(growth, ret_fwd, method="spearman", use="complete.obs")),
              ic0 = suppressWarnings(cor(growth, ret_cur, method="spearman", use="complete.obs")),
              n = .N), by = sig_date][n >= 30]
nw_t <- function(x, lag) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n; s <- g0
  if (lag > 0) for (l in 1:min(lag, n-1)) s <- s + 2*(1 - l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if (!is.finite(s) || s <= 0) return(NA_real_)
  m / sqrt(s/n)
}
say("")
say("=== ★PIT offset 스캔 (성장 합성 스코어) ===")
say("  offset +1 (forward, 본 라운드 컨벤션): rank-IC 평균 %.4f · t_NW3 %.3f · n=%d월",
    mean(ics$ic1, na.rm=TRUE), nw_t(ics$ic1, 3), sum(!is.na(ics$ic1)))
say("  offset  0 (동시월)                  : rank-IC 평균 %.4f · t_NW3 %.3f · n=%d월",
    mean(ics$ic0, na.rm=TRUE), nw_t(ics$ic0, 3), sum(!is.na(ics$ic0)))
say("  ratio |t0/t1| = %.2f  (FQ-165 M26 은 3.34 — 클수록 동시성 상관 성격)",
    abs(nw_t(ics$ic0,3)/nw_t(ics$ic1,3)))

## ── 3. 섹터 EW 초과수익 r_s,m ───────────────────────────────────────────────
SR <- merge(ELIG[, .(sig_date = Date, Ticker, Sector)], R1, by = c("sig_date","Ticker"))
uni <- SR[, .(uni_ew = mean(ret_fwd)), by = sig_date]
sec <- SR[, .(sec_ew = mean(ret_fwd), n = .N), by = .(sig_date, Sector)]
sec <- merge(sec, uni, by = "sig_date")[, r_s := sec_ew - uni_ew]
sec <- sec[n >= 3]                      # 섹터당 3종목 미만 월은 EW 불안정 → 제외(사전 고정)
say("")
say("섹터 초과수익 패널: %d행 · 섹터 %d · 월 %d (섹터당 >=3종목 월만)",
    nrow(sec), uniqueN(sec$Sector), uniqueN(sec$sig_date))

## ── 4. β_s,t (trailing 60m, 최소 36m, 실현월만) ─────────────────────────────
INF <- ST[!is.na(infl), .(sig_date, infl)][order(sig_date)]
INF[, d_infl := infl - shift(infl)]
say("Δinfl 가용 %d개월 · sd %.4f", sum(!is.na(INF$d_infl)), sd(INF$d_infl, na.rm=TRUE))

M <- merge(sec[, .(sig_date, Sector, r_s)], INF[, .(sig_date, d_infl)], by = "sig_date")
M <- M[!is.na(d_infl)][order(Sector, sig_date)]
sds <- sort(unique(M$sig_date))
idx <- setNames(seq_along(sds), as.character(sds))
## β_s,t 는 sig_date t 시점에 **실현 완료된** 월(m <= t 직전월)만 사용 → 창의 끝을 t-1 로 둔다
beta_rows <- list()
for (s in unique(M$Sector)) {
  ms <- M[Sector == s][order(sig_date)]
  for (i in seq_along(sds)) {
    t_d <- sds[i]
    hist <- ms[sig_date < t_d]            # 엄격히 이전 월만 (실현 완료)
    if (nrow(hist) < 36L) next
    hh <- utils::tail(hist, 60L)
    vv <- stats::var(hh$d_infl)
    if (!is.finite(vv) || vv <= 0) next
    b <- stats::cov(hh$r_s, hh$d_infl) / vv
    beta_rows[[length(beta_rows)+1L]] <- data.table(sig_date = t_d, Sector = s,
                                                    beta = b, n_win = nrow(hh))
  }
}
BETA <- rbindlist(beta_rows)
say("β_s 패널 %d행 · 섹터 %d · sig_date %d (%s ~ %s)",
    nrow(BETA), uniqueN(BETA$Sector), uniqueN(BETA$sig_date),
    as.character(min(BETA$sig_date)), as.character(max(BETA$sig_date)))
say("β 분포: 중앙 %.4f · sd %.4f · [%.3f, %.3f]",
    median(BETA$beta), sd(BETA$beta), min(BETA$beta), max(BETA$beta))

## ── 5. primary falsification — β_s 부호 vs 채널 예측 ────────────────────────
pos_exp <- c("에너지","화학","철강","비철,목재등","상사,자본재")
neg_exp <- c("유틸리티","통신서비스","소프트웨어","건강관리","미디어,교육")
PRED <- rbind(data.table(Sector = pos_exp, pred = 1L), data.table(Sector = neg_exp, pred = -1L))
say("")
say("=== primary: β_s 부호-채널 정합 (예측 부여 %d 섹터, 사전 고정) ===", nrow(PRED))
BP <- merge(BETA, PRED, by = "Sector")
BP[, hit := as.integer(sign(beta) == pred)]
say("  전체 일치율 %.3f (n=%d 섹터-월) — 문턱 0.50", mean(BP$hit), nrow(BP))
## stride-12 부분표본 (겹치는 창 보정)
sd_beta <- sort(unique(BETA$sig_date))
stride <- sd_beta[seq(1, length(sd_beta), by = 12)]
say("  stride-12 부분표본 일치율 %.3f (n=%d)", mean(BP[sig_date %in% stride]$hit),
    nrow(BP[sig_date %in% stride]))
persec <- BP[, .(hit_rate = mean(hit), n = .N, mean_beta = mean(beta),
                 pred = pred[1]), by = Sector][order(-hit_rate)]
print(persec)
## 이항 검정 (stride-12 근사 독립)
bs <- BP[sig_date %in% stride]
bt <- stats::binom.test(sum(bs$hit), nrow(bs), p = 0.5)
say("  stride-12 이항검정: p = %.4f (95%%CI %.3f~%.3f)", bt$p.value, bt$conf.int[1], bt$conf.int[2])

## ── 6. F2 — β_s 부호 안정성 (stride-12 창 간 반전율) ────────────────────────
say("")
say("=== F2: β_s 부호 안정성 (stride-12 창 간 반전율, 문턱 30%%) ===")
f2 <- BETA[sig_date %in% stride][order(Sector, sig_date)]
f2[, flip := as.integer(sign(beta) != shift(sign(beta))), by = Sector]
f2r <- f2[!is.na(flip), .(flip_rate = mean(flip), n = .N), by = Sector][order(-flip_rate)]
print(f2r)
say("  예측 부여 10섹터 평균 반전율 %.3f", mean(f2r[Sector %in% PRED$Sector]$flip_rate))
say("  전 섹터 평균 반전율 %.3f", mean(f2r$flip_rate))
## β_s 계열 위 t 검정은 NW lag >= 창(60)
say("  (참고) 섹터별 β 평균의 NW lag60 t — 예측 부여 섹터만:")
for (s in PRED$Sector) {
  b <- BETA[Sector == s][order(sig_date)]$beta
  if (length(b) < 70) { say("    %-14s n=%d (부족)", s, length(b)); next }
  say("    %-14s mean_beta %+.4f · t_NW60 %+.2f · (t_NW3 %+.2f — 겹치는 창에 lag3 을 쓰면 이만큼 부풀음)",
      s, mean(b), nw_t(b, 60), nw_t(b, 3))
}

saveRDS(list(SC = SC, GW = GW, sec = sec, BETA = BETA, INF = INF, ics = ics, pw = pw,
             PRED = PRED, persec = persec, f2r = f2r, stride = stride),
        file.path(OUT, "layers.rds"))
say("")
say("저장: %s/layers.rds", OUT)
