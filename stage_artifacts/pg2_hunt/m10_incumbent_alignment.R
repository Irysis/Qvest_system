## m10 — ★★최우선: bm_load_incumbent() 내부 조인이 어긋났는가
## m9 ①: cor(inc$ret_net, inc$benchmark_ret) = **0.666**, β 0.706.
##   long-only KR 북은 β~0.92(메모리 카드 확립치) ⇒ 0.706 은 낮다.
## m9 ②: 슬리브 r 은 inc 의 **m+1** 벤치와 정렬(10/12).
##   ⇒ 가설: inc$benchmark_ret 이 inc$ret_net 대비 **1개월 낡았다**(두 CSV 를 따로 읽어 붙인 조인 결함).
## ★영향 범위가 크다 — 사실이면 이 아크의 **모든 ΔIR·rho·active** 가 잘못된 벤치 위에 있다.
## ★판정 = 원천 CSV 를 직접 읽어 오프셋 스캔. 최대 상관 지점이 0 이 아니면 결함 확정.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/report_guard.R")
say <- function(fmt, ...) say_guarded(fmt, ..., prefix = "[m10] ")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

say("=== ① bm_load_incumbent 산출 ===")
inc <- bm_load_incumbent(); inc[, m := mi(date)]
say("  n %d · 기간 %s ~ %s", nrow(inc), min(inc$date), max(inc$date))
say("  cor(ret_net, benchmark_ret) **%.4f** · β **%.4f**",
    cor(inc$ret_net, inc$benchmark_ret), unname(coef(lm(ret_net ~ benchmark_ret, inc))[2]))

say("=== ② 원천 CSV 직접 판독 ===")
pr <- Sys.glob(file.path(ROOT, "**/03_period_returns.csv"))
bp <- Sys.glob(file.path(ROOT, "**/05_benchmark_returns.csv"))
if (!length(pr)) { pr <- list.files(ROOT, "^03_period_returns\\.csv$", recursive=TRUE, full.names=TRUE)
                   bp <- list.files(ROOT, "^05_benchmark_returns\\.csv$", recursive=TRUE, full.names=TRUE) }
say("  period_returns 후보 %d · benchmark_returns 후보 %d", length(pr), length(bp))
pick <- function(v) v[which.max(file.info(v)$size)]
A <- fread(pick(pr)); B <- fread(pick(bp))
say("  A(%s): %d행 · 열 = %s", basename(pick(pr)), nrow(A), paste(head(names(A),8), collapse=","))
say("  B(%s): %d행 · 열 = %s", basename(pick(bp)), nrow(B), paste(head(names(B),8), collapse=","))
dcA <- names(A)[which(tolower(names(A)) %in% c("date","ym","period","realized_ym"))[1]]
dcB <- names(B)[which(tolower(names(B)) %in% c("date","ym","period","realized_ym"))[1]]
rcA <- names(A)[which(tolower(names(A)) %in% c("ret_net","return","ret","portfolio_return"))[1]]
rcB <- names(B)[which(tolower(names(B)) %in% c("benchmark_ret","bm_ret","return","ret","benchmark"))[1]]
say("  키/값 열: A[%s , %s] · B[%s , %s]", dcA, rcA, dcB, rcB)
A2 <- data.table(m = mi(as.Date(as.character(A[[dcA]]))), ra = as.numeric(A[[rcA]]))[!is.na(m)]
B2 <- data.table(m = mi(as.Date(as.character(B[[dcB]]))), rb = as.numeric(B[[rcB]]))[!is.na(m)]
say("  A 월범위 %d~%d (n %d) · B 월범위 %d~%d (n %d)", min(A2$m), max(A2$m), nrow(A2), min(B2$m), max(B2$m), nrow(B2))

say("=== ③ ★오프셋 스캔 — 원천 두 계열 (0 이 최대여야 정상) ===")
cs <- vapply(-3:3, function(k) { Z <- merge(A2, B2[, .(m = m + k, rb)], by="m")
  if (nrow(Z) < 40) return(NA_real_); suppressWarnings(cor(Z$ra, Z$rb, use="complete.obs")) }, numeric(1))
for (i in seq_along(-3:3)) say("  offset %+d : cor **%.4f**%s", (-3:3)[i], cs[i],
  if (which.max(cs) == i) "  ← 최대" else "")
pk <- (-3:3)[which.max(cs)]
say("  ⇒ **%s**", if (pk == 0L) "원천 정렬 정상 — 0.666 은 조인 결함 아님(북 자체 성질)" else
  sprintf("★★원천 조인 결함 확정 — benchmark 를 %+d 개월 밀어야 맞는다", pk))

say("=== ④ 대안 설명 — 북이 원래 저베타인가 (오버레이 북이면 정상) ===")
Z0 <- merge(A2, B2, by="m")
say("  offset0: cor %.4f · β %.4f · sd(book) %.4f · sd(bm) %.4f · n %d",
    cor(Z0$ra, Z0$rb), unname(coef(lm(ra ~ rb, Z0))[2]), sd(Z0$ra), sd(Z0$rb), nrow(Z0))
Zb <- merge(A2, B2[, .(m = m + pk, rb)], by="m")
say("  offset%+d: cor %.4f · β %.4f · n %d", pk, cor(Zb$ra, Zb$rb), unname(coef(lm(ra ~ rb, Zb))[2]), nrow(Zb))
say("  ★PG2 = R05 vol 오버레이 + AR 임계 북이다 — **노출을 줄이는 오버레이가 β 를 낮춘다**")
say("  ⇒ β %.3f 가 오버레이 산물이면 정상. 오프셋 스캔이 0 최대면 **결함 아님**이 확정된다", unname(coef(lm(ra ~ rb, Z0))[2]))

say("=== ⑤ 그렇다면 m9 ②의 슬리브 +1 은 무엇인가 ===")
say("  슬리브는 raw long-only(오버레이 없음)라 β~0.9 여야 하는데 offset0 상관이 ~0 이었다.")
say("  ⇒ 두 사실이 양립하려면 **슬리브 계열의 월 라벨 규약이 inc 와 1개월 다르다**(파일별 realized_ym vs anchor).")
say("  ★이건 inc 결함이 아니라 **내 수동 merge 결함**이며, bm_delta_ir 내부 정렬(+2)과도 별개 축이다.")
say("=== m10 완료 ===")
