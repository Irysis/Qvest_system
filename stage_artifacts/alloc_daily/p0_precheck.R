## 배분 축 복귀 (도훈 원 가설) — P0: 일간 프레임이 **에피소드 구속을 실제로 푸는가**
## ★함정 경고: 일간으로 내리면 n 은 439 → ~9,000 으로 늘지만 **위기 에피소드 수는 그대로**다.
##   FQ-176 에서 유효표본을 개월수로 셌다가 틀린 것과 같은 실수를 관측단위만 바꿔 반복할 수 있다.
##   따라서 이 precheck 가 판정한다: 일간 MDE 가 월간 대비 실제로 낮아지는가, 아니면 클러스터에서 도로 사라지는가.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/alloc_daily")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

## ---- 1. 일간 벤치 확보 (입력 실측 — 가정 금지) -------------------------------
say("=== 1. 일간 벤치 입력 실측 ===")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","BM_Ret")))
RAW[, Date := as.Date(Date)]
say("  RAWDATA(BM_Ret 열) %d행 · 고유일자 %d · %s ~ %s",
    nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
BD <- unique(RAW[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
dup <- BD[, .N, by = Date][N > 1]
say("  일자별 고유 BM_Ret 추출: %d행 · 중복일자 %d건 %s",
    nrow(BD), nrow(dup), if (nrow(dup)) "★일자당 값이 여럿 — 확인 필요" else "(1일 1값 확인)")
if (nrow(dup)) { BD <- BD[, .(BM_Ret = BM_Ret[1]), by = Date][order(Date)]
                 say("  ★중복은 첫 값으로 축약 — 그 사실을 기록(침묵 아님)") }
say("  일간 수익 실측: 평균 %+.5f · sd %.5f · 관측 %d일 · 연환산 sd %.2f%%",
    mean(BD$BM_Ret), sd(BD$BM_Ret), nrow(BD), sd(BD$BM_Ret)*sqrt(252)*100)
say("  자기상관 lag1 %.3f · lag5 %.3f (일간 수익은 거의 무상관이어야 정상)",
    acf(BD$BM_Ret, 5, plot=FALSE)$acf[2], acf(BD$BM_Ret, 6, plot=FALSE)$acf[6])

## ---- 2. 일간 낙폭 심도 + 사건 정의 -------------------------------------------
n <- nrow(BD); nav <- cumprod(1 + BD$BM_Ret)
roll_max <- frollapply(nav, 252, max, fill = NA, align = "right")
BD[, dd252 := nav / roll_max - 1]
BD[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
BD[, fwd20 := frollsum(shift(BM_Ret, 1L, type="lead"), 20, align = "left", fill = NA)]
say("=== 2. 일간 심도 === dd252 비결측 %d · 범위 %.3f ~ %.3f", sum(!is.na(BD$dd252)),
    min(BD$dd252,na.rm=TRUE), max(BD$dd252,na.rm=TRUE))

## ---- 3. ★핵심: 에피소드 수는 관측단위를 바꿔도 그대로인가 --------------------
say("=== 3. ★에피소드 구조 — 관측단위를 바꿔도 그대로인가 ===")
for (thr in c(-0.10, -0.20, -0.30)) {
  on <- !is.na(BD$dd252) & BD$dd252 <= thr
  r <- rle(on); ne <- sum(r$values)
  lens <- r$lengths[r$values]
  say("  dd252 <= %.0f%% : ON %d일(%.1f%%) · **에피소드 %d개** · 길이 중앙 %.0f일 최장 %d일",
      thr*100, sum(on), 100*mean(on), ne, median(lens), max(lens))
}
say("  ★대조: 월간 프레임의 dd12<=-20% 는 ON 46개월 / 에피소드 4개였다.")

## ---- 4. MDE 3종 대조 — 순진 vs HAC vs 에피소드-클러스터 ----------------------
say("=== 4. ★MDE 대조 (착수 자격 판정) ===")
nw_se <- function(x, lag) {              # 평균의 HAC se
  n <- length(x); m <- mean(x); e <- x - m
  s <- sum(e^2)/n
  for (l in seq_len(lag)) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  sqrt(max(s, 0)/n)
}
res <- list()
for (thr in c(-0.10, -0.20, -0.30)) {
  D <- BD[!is.na(dd252) & !is.na(fwd1)]
  on <- D$dd252 <= thr
  if (sum(on) < 50) next
  d1 <- mean(D$fwd1[on]) - mean(D$fwd1[!on])
  ## (a) 순진 (독립 가정)
  se_naive <- sd(D$fwd1) * sqrt(1/sum(on) + 1/sum(!on))
  ## (b) HAC lag 20 (약 1개월)
  se_hac <- sqrt(nw_se(D$fwd1[on], 20)^2 + nw_se(D$fwd1[!on], 20)^2)
  ## (c) 에피소드-클러스터
  r <- rle(on); ne <- sum(r$values)
  se_cl <- se_naive * sqrt(sum(on)/max(1, ne))
  say("  dd252<=%.0f%% (ON %d일 · 에피소드 %d):", thr*100, sum(on), ne)
  say("    효과 %+.5f/일 (연 %+.2f%%) · MDE 순진 %.5f(연 %.2f%%) · HAC20 %.5f(연 %.2f%%) · 클러스터 %.5f(연 %.2f%%)",
      d1, d1*252*100, 2*se_naive, 2*se_naive*252*100, 2*se_hac, 2*se_hac*252*100,
      2*se_cl, 2*se_cl*252*100)
  say("    ratio: 순진 %.2f · HAC %.2f · **클러스터 %.2f**",
      abs(d1)/(2*se_naive), abs(d1)/(2*se_hac), abs(d1)/(2*se_cl))
  res[[length(res)+1L]] <- data.table(thr = thr*100, n_on = sum(on), n_epi = ne,
    eff_ann = d1*252*100, mde_naive_ann = 2*se_naive*252*100,
    mde_hac_ann = 2*se_hac*252*100, mde_cl_ann = 2*se_cl*252*100,
    ratio_naive = abs(d1)/(2*se_naive), ratio_hac = abs(d1)/(2*se_hac),
    ratio_cl = abs(d1)/(2*se_cl))
}
R <- rbindlist(res)
say("=== 5. ★착수 자격 판정 (사전 고정) ===")
say("  규칙: **클러스터 기준** ratio 가 월간 프레임(0.59) 을 유의미하게 상회해야 착수 자격.")
say("  월간 배분축 MDE = 연 24.6~87.7%% vs 관측 4.7~23.4%% (전건 미달)")
say("  일간 클러스터 MDE 범위 = 연 %.2f%% ~ %.2f%% · 관측 효과 = 연 %.2f%% ~ %.2f%%",
    min(R$mde_cl_ann), max(R$mde_cl_ann), min(R$eff_ann), max(R$eff_ann))
say("  ★max ratio(클러스터) = %.3f  -> %s", max(R$ratio_cl),
    if (max(R$ratio_cl) >= 1.0) "착수 자격 있음" else
    if (max(R$ratio_cl) >= 0.7) "경계 — 설계 보강 후 재판정" else "★미달 — 착수 전 폐기")
say("  ⚠순진 ratio(%.2f)와 클러스터 ratio(%.2f)의 격차 = **관측단위를 내려도 에피소드가 묶는다**는 증거",
    max(R$ratio_naive), max(R$ratio_cl))

fwrite(R, file.path(OUT, "p0_mde.csv"))
saveRDS(list(BD = BD, mde = R), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
