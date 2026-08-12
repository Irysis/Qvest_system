## P8a-recon — 분해가 포트폴리오 실측과 회계적으로 맞는가 (항등 검증)
## 사전등록: P8a 의 랭크 프로파일로 top-25 EW 초과수익을 재구성하면
##   (a) 무밴드 arm 의 순서(mine 1.292 < core4 1.704)를 재현해야 하고
##   (b) mine 밴드 arm 의 gross 개선이 실측 net 개선(+2.327%p, ai1: 5.372→7.699)보다
##       회전 비용만큼 크게 나와야 한다. 안 맞으면 분해가 기전이 아니다.
## ★새 성과 주장 없음. 이미 측정된 수치들 사이의 항등 점검.
suppressPackageStartupMessages(library(jsonlite))
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
R <- as.data.frame(fromJSON(file.path(OUT, "p8a_result.json"))$results)

f <- function(b, k) R[R$base == b, k]
recon <- function(b) {
  nb <- (13*f(b,"r1_13") + 12*f(b,"r14_25")) / 25            # 무밴드 top-25 EW
  bd <- (13*f(b,"r1_13") + 12*(f(b,"r14_25") + f(b,"swap_d_ann"))) / 25
  data.frame(base=b, noband_gross=round(nb,3), band_gross=round(bd,3), gross_gain=round(bd-nb,3))
}
X <- do.call(rbind, lapply(R$base, recon))
X$port_t_noband <- c(1.292, 2.855, 1.704)   # 기측정: ai1 / P1e / P6c
print(X)

ord_ok <- X$noband_gross[X$base=="core4-EW"] > X$noband_gross[X$base=="mine(M26)"]
cat(sprintf("\n(a) 무밴드 순서 재현 (core4 > mine): %s  [%.3f vs %.3f, PORT_t 1.704 vs 1.292]\n",
            ord_ok, X$noband_gross[X$base=="core4-EW"], X$noband_gross[X$base=="mine(M26)"]))
g <- X$gross_gain[X$base=="mine(M26)"]; net <- 7.699 - 5.372
cat(sprintf("(b) mine 밴드: gross %+.3f%%p vs 실측 net %+.3f%%p → 잔차 %+.3f%%p (= 회전 비용이어야 함)\n",
            g, net, g - net))
cost_ok <- (g - net) > 0 && (g - net) < 2.0
verdict <- if (ord_ok && cost_ok) "R1_IDENTITY_HOLDS" else "R2_IDENTITY_BROKEN"
cat(sprintf("판정: %s\n", verdict))
write_json(list(verdict=verdict, order_reproduced=ord_ok, gross_gain=g, net_gain=net,
                implied_cost=g-net, table=X), file.path(OUT,"p8a_recon.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
