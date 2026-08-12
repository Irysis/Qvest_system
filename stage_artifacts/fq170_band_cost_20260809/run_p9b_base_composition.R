## P9b — P9a 의 40 base 가 한 계열에 몰려 있는가 (유효 n 점검)
## 사전등록: P9a 는 331 후보 중 `cand[1:40]` 로 **앞에서 잘랐다**(무작위 아님).
##  접두 계열이 한둘이면 유효 n 이 40보다 훨씬 작고 rho 0.39 의 유의는 과대평가다.
##  ★추가 통제: base 간 예측자/결과의 **계열 내 상관**을 보고 계열-군집 clustered n 을 추정.
##  판정: V1_DIVERSE(계열 >= 5 ∧ 최대계열 비중 <= 0.5) / V2_CLUSTERED
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
R <- fread(file.path(OUT, "p9a_bases.csv"))
R[, fam := sub("^([A-Za-z]+)[0-9_].*$", "\\1", base)]
R[fam == base, fam := substr(base, 1, 3)]
cat(sprintf("[입력] base %d\n", nrow(R)))
cat("\n=== 계열 분포 ===\n"); F <- R[, .N, by=fam][order(-N)]; print(F)
n_fam <- nrow(F); top_share <- F$N[1]/nrow(R)
cat(sprintf("\n계열 %d종 · 최대계열 비중 %.3f (%s %d개)\n", n_fam, top_share, F$fam[1], F$N[1]))
cat("\n=== base 목록 ===\n"); print(R[order(base), .(base, fam, n_months, slope_all=round(slope_all,2), swap_all=round(swap_all,2))])

## 계열-군집 보수 추정: 계열 수를 유효 n 으로 보고 임계 재산출
sp <- function(x,y) suppressWarnings(cor(x,y,method="spearman"))
r_oe <- sp(R$slope_odd, R$swap_evn); r_eo <- sp(R$slope_evn, R$swap_odd)
crit <- function(n) { tc <- qt(0.975, max(n-2,1)); sqrt(tc^2/(tc^2+max(n-2,1))) }
cat(sprintf("\n교차 rho: %.3f / %.3f\n임계 @ n=%d(전체) = %.3f · @ n=%d(계열수, 보수) = %.3f\n",
            r_oe, r_eo, nrow(R), crit(nrow(R)), n_fam, crit(n_fam)))
survives_cons <- min(abs(r_oe), abs(r_eo)) >= crit(n_fam)
cat(sprintf("보수 임계에서도 생존: %s\n", survives_cons))
## 계열별 재현: 각 계열 안에서도 부호가 같은가 (군집이면 계열별로 갈릴 것)
byfam <- R[, .(n=.N, rho_all = if (.N >= 4) sp(slope_all, swap_all) else NA_real_), by=fam][order(-n)]
cat("\n=== 계열 내 재현(동일표본 rho, n>=4 계열만) ===\n"); print(byfam)
verdict <- if (n_fam >= 5L && top_share <= 0.5) "V1_DIVERSE" else "V2_CLUSTERED"
cat(sprintf("\n판정: %s%s\n", verdict, if (!survives_cons) "  ⚠보수 임계 미달 — rho 를 계열수 기준으로도 주장하지 말 것" else ""))
write_json(list(verdict=verdict, n_base=nrow(R), n_fam=n_fam, top_share=top_share,
                rho_odd_even=r_oe, rho_even_odd=r_eo, crit_full=crit(nrow(R)),
                crit_family=crit(n_fam), survives_conservative=survives_cons,
                families=F, by_family=byfam),
           file.path(OUT,"p9b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
