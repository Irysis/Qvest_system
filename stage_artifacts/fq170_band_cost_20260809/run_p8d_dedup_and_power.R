## P8d — P8c 마무리: (1) z_raw ≡ Q01_EB 중복 확인 (2) 중복 제거 후 재계산 (3) 검정력
## 사전등록(측정 전 고정):
##  P8c 에서 z_raw 와 Q01_EB 가 slope/swap/strength 세 통계량 모두 소수3자리 동일.
##  중복이면 상관에 같은 점이 두 번 들어가 **n 을 부풀리고 상관을 편향**시킨다.
##  (1) 두 열의 원자료 동일성을 직접 확인(상관 아닌 **값 일치율**).
##  (2) 중복 제거 후 교차분할 spearman 재계산.
##  (3) n_base 에서 spearman 유의 임계(양측 5%)를 산출해 **무엇을 주장할 수 있는지** 명시.
##  ★새 성과 측정 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

## (1) 원자료 동일성 — 값 자체를 본다
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
x <- B$z_raw; y <- B$Q01_EB
both <- !is.na(x) & !is.na(y)
ident <- sum(x[both] == y[both]); rk <- suppressWarnings(cor(x[both], y[both], method="spearman"))
cat(sprintf("(1) z_raw vs Q01_EB: 공통 비결측 %d · **값 완전일치 %d (%.4f)** · spearman %.6f\n",
            sum(both), ident, ident/sum(both), rk))
dup_exact <- ident == sum(both)
dup_rank  <- is.finite(rk) && abs(rk) > 0.9999
cat(sprintf("    값 동일: %s · 순위 동일(단조변환): %s\n", dup_exact, dup_rank))

## (2) 중복 제거 재계산
R <- fread(file.path(OUT, "p8c_split.csv"))
drop <- if (dup_exact || dup_rank) "z_raw" else NA_character_
RD <- if (!is.na(drop)) R[base != drop] else copy(R)
cat(sprintf("(2) base %d → %d (제거: %s)\n", nrow(R), nrow(RD), ifelse(is.na(drop),"없음",drop)))
sp <- function(a,b) suppressWarnings(cor(a, b, method="spearman"))
tab <- data.table(
  predictor = c("slope","slope","strength_r1_25","strength_r1_25"),
  direction = c("odd→even","even→odd","odd→even","even→odd"),
  rho_full  = round(c(sp(R$slope_odd,R$swap_evn), sp(R$slope_evn,R$swap_odd),
                      sp(R$str_odd,R$swap_evn),   sp(R$str_evn,R$swap_odd)), 3),
  rho_dedup = round(c(sp(RD$slope_odd,RD$swap_evn), sp(RD$slope_evn,RD$swap_odd),
                      sp(RD$str_odd,RD$swap_evn),   sp(RD$str_evn,RD$swap_odd)), 3))
print(tab)

## (3) 검정력 — spearman 유의 임계 (t 근사)
n <- nrow(RD); tc <- qt(0.975, n-2); rho_crit <- sqrt(tc^2 / (tc^2 + n - 2))
cat(sprintf("\n(3) n_base=%d 에서 spearman 양측5%% 임계 |rho| = %.3f\n", n, rho_crit))
sig <- tab$rho_dedup[abs(tab$rho_dedup) >= rho_crit]
cat(sprintf("    임계 초과 항목: %d / 4\n", length(sig)))
best <- tab[which.max(abs(tab$rho_dedup))]
cat(sprintf("    최강 = %s %s rho %.3f (%s)\n", best$predictor, best$direction, best$rho_dedup,
            ifelse(abs(best$rho_dedup) >= rho_crit, "유의", "**비유의**")))
need_n <- ceiling((tc^2 * (1 - 0.45^2) / 0.45^2) + 2)
cat(sprintf("    rho=0.45 를 유의하게 검출하려면 base 약 %d개 필요 (현재 %d)\n", need_n, n))
verdict <- if (length(sig) > 0) "B1_SOME_SURVIVES_SIGNIFICANT" else "B2_ALL_UNDERPOWERED"
cat(sprintf("판정: %s\n", verdict))
if (verdict == "B2_ALL_UNDERPOWERED")
  cat("⇒ 아티팩트 제거 후 **어느 예측자도 n=%d 에서 유의하지 않다**. 사전판정 규칙 미확립.\n")
write_json(list(verdict=verdict, dup_exact=dup_exact, dup_rank=dup_rank, dropped=drop,
                n_base=n, rho_crit=rho_crit, needed_n_for_045=need_n, table=tab),
           file.path(OUT,"p8d_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
