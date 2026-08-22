## WT-D20260822_008 (FQ-246 NP2) P5 — ★정답지 자체에 식별 가능한 정체가 있는가 (분할표본 전이)
## 동기: 기준이 무지하다는 결과 앞에서 "기준이 나쁜가" 와 "표적이 애초에 식별 불가한가" 는 처분이 다르다.
##       표적을 **같은 달 안에서 절반 유니버스로 나눠** 한쪽에서 고르고 다른 쪽에서 평가하면,
##       그 달의 '옳은 팩터' 가 표본-무관한 정체를 갖는지(=예측 가능성의 전제)를 직접 잰다.
## ★전 산출 진단 라벨 · capital_eligible=FALSE (정답지는 사후 정보).
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_008"
P1 <- readRDS(file.path(OUT,"p1_parity.rds")); G <- readRDS(file.path(OUT,"p3_gate.rds"))
K <- P1$K; NM <- P1$NM; TOPN <- P1$TOPN; Zl <- P1$Zl; RBF <- P1$ret_by_factor
CRIT <- P1$CRIT; AM <- P1$AM; DIRS <- P1$DIRS

NHALF <- max(10L, floor(TOPN/2))   # 반쪽 유니버스에서의 상위 편입 수 (25 -> 12)
cat(sprintf("반쪽 유니버스 상위 편입 수 = %d (전체 top-%d 의 절반 규격)\n", NHALF, TOPN))
univ_n <- vapply(Zl, function(z) length(z$tick), 0L)
cat(sprintf("월별 유니버스 크기: 중앙 %d · 최소 %d · 최대 %d\n",
            as.integer(median(univ_n)), min(univ_n), max(univ_n)))

ret_half <- function(m, idx) { Z <- Zl[[m]]$Z[idx,,drop=FALSE]; f <- Zl[[m]]$fwd[idx]
  vapply(seq_len(K), function(k){ v <- Z[,k]; ok <- is.finite(v)&is.finite(f)
    if (sum(ok) < NHALF) return(NA_real_)
    mean(f[ok][order(v[ok], decreasing=TRUE)[seq_len(NHALF)]]) }, 0) }
ic_half <- function(m, idx) { Z <- Zl[[m]]$Z[idx,,drop=FALSE]; f <- Zl[[m]]$fwd[idx]
  vapply(seq_len(K), function(k){ v <- Z[,k]; ok <- is.finite(v)&is.finite(f)
    if (sum(ok) < 30L) return(NA_real_); cor(rank(v[ok]), rank(f[ok])) }, 0) }

R <- 20L; set.seed(20260822L)
res <- vector("list", R)
for (r in seq_len(R)) {
  vA <- vB <- matrix(NA_real_, NM, K); iA <- matrix(NA_real_, NM, K)
  for (m in seq_len(NM)) { n <- length(Zl[[m]]$tick); s <- sample.int(n)
    hA <- s[seq_len(floor(n/2))]; hB <- s[(floor(n/2)+1):n]
    vA[m,] <- ret_half(m,hA); vB[m,] <- ret_half(m,hB); iA[m,] <- ic_half(m,hA) }
  ok <- apply(is.finite(vA)&is.finite(vB), 1, all) & apply(is.finite(iA),1,all)
  mm <- which(ok)
  cen <- function(M,m,k) M[m,k] - mean(M[m,])
  pickA_ret <- vapply(mm, function(m) which.max(vA[m,]), 0L)
  pickA_ic  <- vapply(mm, function(m) which.max(iA[m,]), 0L)
  vv <- data.table(
    transfer_ret = vapply(seq_along(mm), function(j) cen(vB, mm[j], pickA_ret[j]), 0),
    transfer_ic  = vapply(seq_along(mm), function(j) cen(vB, mm[j], pickA_ic[j]), 0),
    oracle_B     = vapply(mm, function(m) max(vB[m,]) - mean(vB[m,]), 0),
    random_B     = vapply(mm, function(m) cen(vB, m, sample.int(K,1)), 0),
    agree_AB     = as.numeric(vapply(seq_along(mm), function(j)
                      pickA_ret[j] == which.max(vB[mm[j],]), TRUE)))
  res[[r]] <- data.table(rep=r, n_months=length(mm),
    transfer_ret_ann=mean(vv$transfer_ret)*12*100, transfer_ret_t=.nw_t_mean(vv$transfer_ret,lag=3L),
    transfer_ic_ann =mean(vv$transfer_ic)*12*100,  transfer_ic_t =.nw_t_mean(vv$transfer_ic,lag=3L),
    oracle_B_ann=mean(vv$oracle_B)*12*100, random_B_ann=mean(vv$random_B)*12*100,
    agree_AB=mean(vv$agree_AB))
}
RES <- rbindlist(res)
cat("\n=== 분할표본 전이 (R=20 무작위 분할 평균) ===\n")
SUM <- RES[, .(n_months=median(n_months),
  transfer_ret_ann=mean(transfer_ret_ann), transfer_ret_t=mean(transfer_ret_t),
  transfer_ic_ann=mean(transfer_ic_ann), transfer_ic_t=mean(transfer_ic_t),
  oracle_B_ann=mean(oracle_B_ann), random_B_ann=mean(random_B_ann),
  agree_AB=mean(agree_AB), sd_transfer=sd(transfer_ret_ann))]
print(SUM[, lapply(.SD, function(x) if (is.numeric(x)) round(x,4) else x)])
cat(sprintf("\n★반쪽-A 의 실현수익 argmax 가 반쪽-B 에서 내는 값 = %+.4f %%p/yr (NW3 t %.3f)\n",
            SUM$transfer_ret_ann, SUM$transfer_ret_t))
cat(sprintf("★같은 달 반쪽-B 의 오라클 상한 = %+.4f %%p/yr · 무작위 픽 = %+.4f %%p/yr\n",
            SUM$oracle_B_ann, SUM$random_B_ann))
cat(sprintf("★전이 비율 = %.4f (= 전이값 / 반쪽 오라클 상한)\n", SUM$transfer_ret_ann/SUM$oracle_B_ann))
cat(sprintf("★A-B 승자 정체 일치율 = %.4f (우연 %.4f)\n", SUM$agree_AB, 1/K))
cat(sprintf("★비교: 반쪽-A 의 rank-IC argmax 가 반쪽-B 에서 내는 값 = %+.4f %%p/yr (t %.3f)\n",
            SUM$transfer_ic_ann, SUM$transfer_ic_t))

cat("\n=== 해석 계산 ===\n")
cat(sprintf("  전이 t 가 유의(>=1.96) = %s · 전이값이 무작위 픽을 초과 = %s\n",
            SUM$transfer_ret_t >= 1.96, SUM$transfer_ret_ann > SUM$random_B_ann))
cat("  ⇒ 유의하면: 그 달의 '옳은 팩터' 는 표본-무관 정체를 갖는다 = 원리적으로 예측 가능한 표적.\n")
cat("     그렇다면 본 라운드 null 의 귀속은 **표적 부재가 아니라 기준 부재**다.\n")
cat("  ⇒ 무의하면: ORACLE_K_RET 상한의 상당분은 월내 잡음-최대화 아티팩트이고,\n")
cat("     그 상한을 분모로 쓴 회수율 서술 전체가 과대 분모를 쓰고 있었다는 뜻이다.\n")

## 정답지 두 판의 값 분해 (승계 규약 6 — 이름·단위 병기)
cat(sprintf("\n[승계 앵커 대조] SELSPACE_headroom_ann_pct(전체 유니버스 top-25 공간) = %+.6f %%p/yr\n",
            P1$selspace_head))
cat(sprintf("                 SELSPACE_value_of_IC_key_ann_pct                    = %+.6f %%p/yr (%.1f%%)\n",
            P1$selspace_head_ic, P1$selspace_head_ic/P1$selspace_head*100))
cat("  ⚠둘 다 canonical_screen_bt 를 통과한 ORACLE_K_RET paired 31.492558 %p/yr 와 다른 양이다.\n")

saveRDS(list(RES=RES, SUM=SUM, NHALF=NHALF, R=R, univ_n=univ_n), file.path(OUT,"p5_target_identity.rds"))
cat("\n[saved] p5_target_identity.rds\nOK\n")
