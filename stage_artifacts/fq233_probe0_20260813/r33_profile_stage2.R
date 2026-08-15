## R33 stage2 — D03_RealVol 5점 분위 프로파일 (수정 프레임)
## 입력: r33_inputs.rds (stage1 산출 — fl = 팩터 Z_Score_Aligned + anchor, frd = Date/Ticker/Ret_1m)
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/fq233_probe0_20260813/r33_profile_stage2.R")'
suppressPackageStartupMessages({library(data.table); library(arrow)})
OUT <- "stage_artifacts/fq233_probe0_20260813"

inp <- readRDS(file.path(OUT, "r33_inputs.rds"))
fl  <- as.data.table(inp$fl); frd <- as.data.table(inp$frd)
frd[, Date := as.Date(Date)]

cat("=== 1) 유니버스 K200 ∪ KQ150 ===\n")
k200  <- as.data.table(read_parquet(".cache/universe_support/us_k200.parquet"))
kq150 <- as.data.table(read_parquet(".cache/universe_support/us_kq150.parquet"))
cat("  us_k200 컬럼:", paste(names(k200), collapse=", "), "\n")
cat("  us_kq150 컬럼:", paste(names(kq150), collapse=", "), "\n")
## ★결함 2건 수리 (2026-08-13 초판에서 실제로 밟음)
##  ① 이 파일들은 **멤버십 목록이 아니라 전 시장 패널 + 플래그 컬럼**이다(K200 0/1/NA).
##     플래그를 무시하면 전 행이 멤버가 된다. 참값만: K200==1 월중앙 정확히 200 · KQ150==1 은 150.
##  ② Date 컨벤션이 다르다 — 정확일치 join 은 259개월 중 **165개월(64%)만** 남긴다
##     (월말이 휴일인 달의 거래일말 vs 캘린더말). **ym 기준**으로 붙이면 259/259.
##     ★초판은 이 버그로도 월중앙 345종목(≈350)이 나와 **그럴듯해 보였다** — 개수 대조가 아니라
##       **월 수 대조**가 잡았다. [[project-window-confound-beat-my-axis-attribution-20260810]] 계통.
.mem <- function(d, flag) { d <- copy(d)
  stopifnot(all(c("Date","Ticker",flag) %in% names(d)))
  d <- d[get(flag) %in% c(TRUE, 1L, 1, "1", "Y")]
  d[, .(ym = format(as.Date(Date), "%Y%m"), Ticker = as.character(Ticker))] }
uni <- unique(rbindlist(list(.mem(k200, "K200"), .mem(kq150, "KQ150"))))
cat(sprintf("  유니버스(플래그 참) %d행 · %d개월 · 월중앙 %d종목 (기대 ~350)\n",
            nrow(uni), uniqueN(uni$ym), as.integer(median(uni[, .N, by = ym]$N))))

cat("\n=== 2) 조인 (팩터 anchor ↔ forward Date) ===\n")
setkey(frd, Date, Ticker)
d <- merge(fl[, .(Date = anchor, Ticker, z, sig_date)], frd, by = c("Date", "Ticker"))
cat(sprintf("  팩터×forward 조인 %d행 · %d개월\n", nrow(d), uniqueN(d$Date)))
# 유니버스는 sig_date(관측월 말) 기준 멤버십으로 건다 — PIT: 보유 시작 전 정보. 키는 **ym**.
.m_before <- uniqueN(d$Date)
d[, ym := format(sig_date, "%Y%m")]
d <- merge(d, unique(uni[, .(ym, Ticker)]), by = c("ym", "Ticker"))
.m_after <- uniqueN(d$Date)
cat(sprintf("  유니버스 적용 후 %d행 · %d개월 · 월중앙 %d종목\n", nrow(d), .m_after,
            as.integer(median(d[, .N, by = Date]$N))))
## ★조인 손실 감시 — 이론 개수와 대조하지 않으면 '반토막'이 그럴듯한 수치로 통과한다
if (.m_after < .m_before) {
  msg <- sprintf("유니버스 조인이 %d→%d개월로 손실(%.1f%%) — 키 컨벤션 의심",
                 .m_before, .m_after, 100*(1 - .m_after/.m_before))
  if (.m_after < 0.95 * .m_before) stop(msg) else warning(msg, call. = FALSE)
}

cat("\n=== 3) 5분위 프로파일 (월별 분위 → 시계열 평균) ===\n")
d <- d[is.finite(z) & is.finite(Ret_1m)]
d[, nq := .N, by = Date]
d <- d[nq >= 50]                       # 분위가 의미를 갖는 최소 횡단면
d[, q := cut(frank(z, ties.method = "average"), breaks = quantile(frank(z, ties.method="average"),
      probs = seq(0,1,0.2), na.rm = TRUE), include.lowest = TRUE, labels = 1:5), by = Date]
d[, q := as.integer(as.character(q))]

skew <- function(x) { x <- x[is.finite(x)]; n <- length(x); if (n < 3) return(NA_real_)
  m <- mean(x); s <- sqrt(sum((x-m)^2)/n); if (s == 0) return(NA_real_); sum((x-m)^3)/(n*s^3) }

pm <- d[, .(mean_r = mean(Ret_1m), med_r = median(Ret_1m), sk = skew(Ret_1m), n = .N), by = .(Date, q)]
prof <- pm[, .(ann_mean_pct = 100*12*mean(mean_r, na.rm=TRUE),
               ann_med_pct  = 100*12*mean(med_r,  na.rm=TRUE),
               skew         = mean(sk, na.rm=TRUE),
               n_month      = .N), by = q][order(q)]
cat(sprintf("  월 %d · 월중앙 %d종목\n\n", uniqueN(d$Date), as.integer(median(d[, .N, by=Date]$N))))
print(prof)

mn <- prof$ann_mean_pct
cat(sprintf("\n  Q5-Q1 평균 스프레드   : %+.2f%%/yr\n", mn[5]-mn[1]))
cat(sprintf("  Q5-Q1 중앙값 스프레드 : %+.2f%%/yr\n", prof$ann_med_pct[5]-prof$ann_med_pct[1]))
cat(sprintf("  왜도 기울기 Q5-Q1     : %+.4f\n", prof$skew[5]-prof$skew[1]))
mono_up <- all(diff(mn) > 0); mono_dn <- all(diff(mn) < 0)
peak <- which.max(mn); trough <- which.min(mn)
shape <- if (mono_up) "단조 증가" else if (mono_dn) "단조 감소" else
         if (peak %in% 2:4) sprintf("혹(hump)형 — 최고 Q%d", peak) else
         if (trough %in% 2:4) sprintf("U형 — 최저 Q%d", trough) else "비단조(기타)"
cat(sprintf("\n  ★형태 판정: %s   (최고 Q%d %.2f%% · 최저 Q%d %.2f%%)\n", shape, peak, mn[peak], trough, mn[trough]))
cat("\n  [무효 probe0 주장, 대조용] Q1 10.49 / Q2 14.43 / Q3 14.65 / Q4 10.42 / Q5 8.68 (혹형)\n")

saveRDS(list(prof = prof, pm = pm), file.path(OUT, "r33_profile_FIXED.rds"))
cat("\n저장: r33_profile_FIXED.rds\n")
