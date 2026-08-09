## FQ-187 P1 — ★tail_asym@−20% 정면 검증 (도훈 "집요하게 더")
## 배경: 내가 사전등록 1급으로 선언했다가 ratio 0.996 으로 실패 판정하고 **버린** 지표인데,
##   오염 정제 후 ratio 1.008~1.132 로 **문턱을 넘는다**. 오염이 그것을 가리고 있었다.
## ★그러나 경계값(≈2시그마)이고 3문턱 중 1셀뿐이다 — 주장 전에 4축 정면 검증.
## 사전 고정: 이 라운드는 tail_asym 을 **승격시키려는 것이 아니라 죽이려는 것**이다(반증 우선).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ187")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/FQ182/p0.rds"))$D)[order(Date)]
G <- fread(file.path(ROOT, "stage_artifacts/FQ182/p5_bench_stock_gap.csv")); G[, Date := as.Date(Date)]
D <- merge(D, G[, .(Date, gap)], by = "Date", all.x = TRUE)
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]
p99 <- quantile(G$gap, 0.99, na.rm = TRUE)
CL <- D[!is.na(fwd1) & !is.na(dd252) & Date < as.Date("2026-01-01") & (is.na(gap) | gap <= p99)]
say("=== 입력 실측 === 정제표본 %d일 · %s ~ %s (C1+C2)", nrow(CL), min(CL$Date), max(CL$Date))

ta <- function(v) mean(v >= 0.03) - mean(v <= -0.03)
THR <- -0.20
on <- CL$dd252 <= THR
obs <- ta(CL$fwd1[on]) - ta(CL$fwd1[!on])
say("  기준선: ON %d일 · OFF %d일 · tail_asym ON %+.4f / OFF %+.4f / **diff %+.4f**",
    sum(on), sum(!on), ta(CL$fwd1[on]), ta(CL$fwd1[!on]), obs)

## ---- ①순환이동 귀무 (블록부트 se 의 과소평가 전력 우회) ----------------------
say("=== ① 순환이동 귀무 2000회 — dd252 를 위상 이동, 수익은 고정 ===")
set.seed(20260809); n <- nrow(CL); nul <- numeric(0)
for (b in 1:2000) {
  sh <- sample.int(n - 1, 1)
  dds <- c(CL$dd252[(sh+1):n], CL$dd252[1:sh])
  o <- dds <= THR
  if (sum(o) < 100 || sum(!o) < 500) next
  nul <- c(nul, ta(CL$fwd1[o]) - ta(CL$fwd1[!o]))
}
p_two <- mean(abs(nul - mean(nul)) >= abs(obs - mean(nul)))
p_one <- mean(nul >= obs)
say("  귀무 %d draw · 평균 %+.5f · sd %.5f · q95 %+.5f", length(nul), mean(nul), sd(nul), quantile(nul,.95))
say("  ★관측 %+.4f · **p_one %.4f · p_two %.4f**", obs, p_one, p_two)
say("  ⇒ %s", if (p_one < 0.05) "귀무 밖 — 생존" else "★귀무 안 — 반증")

## ---- ②에피소드-클러스터 se --------------------------------------------------
say("=== ② 에피소드-클러스터 se (60일 gap 병합) ===")
idx <- which(on); ne <- if (length(idx)) sum(diff(idx) > 60) + 1L else 1L
se_naive <- sqrt(var(as.numeric(CL$fwd1[on] >= 0.03)) /sum(on) + var(as.numeric(CL$fwd1[!on] >= 0.03))/sum(!on) +
                 var(as.numeric(CL$fwd1[on] <= -0.03))/sum(on) + var(as.numeric(CL$fwd1[!on] <= -0.03))/sum(!on))
se_cl <- se_naive * sqrt(sum(on)/max(1, ne))
say("  ON 에피소드(병합60) %d개 · 순진 se %.5f · 클러스터 se %.5f (팽창 %.2f배)",
    ne, se_naive, se_cl, se_cl/se_naive)
say("  ★클러스터 ratio = %.3f  ⇒ %s", abs(obs)/(2*se_cl),
    if (abs(obs)/(2*se_cl) >= 1) "생존" else "★미달 — 에피소드 보정에서 무너짐")

## ---- ③전방창 (적률 왜도는 h=60 에서 부호 반전했다) ---------------------------
say("=== ③ 전방창 h=1..60 ===")
for (h in c(1,2,3,5,10,20,60)) {
  CL[, fh := frollsum(shift(BM_Ret, 1L, type="lead"), h, align="left", fill=NA)]
  A <- CL[!is.na(fh)]
  oh <- A$dd252 <= THR
  if (sum(oh) < 100) next
  ## 꼬리 문턱을 창 길이에 맞춰 스케일(sqrt-time) — 고정 3%는 h 커지면 무의미
  k <- 0.03 * sqrt(h)
  taf <- function(v) mean(v >= k) - mean(v <= -k)
  d <- taf(A$fh[oh]) - taf(A$fh[!oh])
  nul2 <- numeric(0)
  for (b in 1:300) { sh <- sample.int(nrow(A)-1, 1)
    dds <- c(A$dd252[(sh+1):nrow(A)], A$dd252[1:sh]); o2 <- dds <= THR
    if (sum(o2) < 100 || sum(!o2) < 500) next
    nul2 <- c(nul2, taf(A$fh[o2]) - taf(A$fh[!o2])) }
  say("  h=%2d (꼬리문턱 %.2f%%) : diff %+.4f · 귀무 p_one %.3f", h, k*100, d, mean(nul2 >= d))
}

## ---- ④타 계열 (KR 벤치 고유인가) --------------------------------------------
say("=== ④ 타 계열 재현 — FQ-182 가 만든 계열 재사용 ===")
f <- file.path(ROOT, "stage_artifacts/FQ182/adv_other_markets.csv")
if (file.exists(f)) {
  OM <- fread(f)
  say("  adv_other_markets.csv 사용 가능 — 단 그 파일은 skew 기준이라 tail_asym 는 재산출 필요")
  say("  계열 목록: %s", paste(unique(OM$series), collapse=", "))
} else say("  ★타 계열 원천 부재 — 별도 라운드 필요로 기록")

saveRDS(list(obs = obs, p_one = p_one, p_two = p_two, se_cl = se_cl, n_epi = ne),
        file.path(OUT, "p1.rds"))
say("=== P1 완료 ===")
