suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- fread("stage_artifacts/pg2_hunt/shard0_results.csv")
cat("n_measured:", nrow(R), "\n")
if (file.exists("stage_artifacts/pg2_hunt/shard0_errors.csv")) {
  E <- fread("stage_artifacts/pg2_hunt/shard0_errors.csv"); cat("n_failed:", nrow(E), "\n"); print(E[,.N,by=reason])
} else cat("n_failed: 0\n")
cat("status_uncond:\n"); print(R[,.N,by=status_uncond]); cat("status_park:\n"); print(R[,.N,by=status_park])
cat("align_offset:\n"); print(R[,.N,by=align_offset])
cat("n range uncond:", range(R$n), " parked:", range(R$n_parked), "\n")
q <- function(x) round(quantile(x, c(0,.25,.5,.75,1), na.rm=TRUE), 4)
cat("\n== uncond ==\n cor:", q(R$cor_uncond), "\n ir:", q(R$ir_uncond), "\n dIR:", q(R$dIR_uncond),
    "\n dIR>0:", sum(R$dIR_uncond>0,na.rm=TRUE), "/", sum(is.finite(R$dIR_uncond)),
    "\n cor<0.2:", sum(R$cor_uncond<0.2,na.rm=TRUE), " ir>0.5:", sum(R$ir_uncond>0.5,na.rm=TRUE), "\n")
cat("\n== parked ==\n cor:", q(R$cor_park), "\n ir:", q(R$ir_park), "\n dIR:", q(R$dIR_park),
    "\n dIR>0:", sum(R$dIR_park>0,na.rm=TRUE), "/", sum(is.finite(R$dIR_park)),
    "\n cor<0.2:", sum(R$cor_park<0.2,na.rm=TRUE), " ir>0.5:", sum(R$ir_park>0.5,na.rm=TRUE), "\n")
cat("\npaired (park - uncond) at w=0.20: cor delta med", round(median(R$cor_park-R$cor_uncond,na.rm=TRUE),4),
    " n_lower:", sum(R$cor_park<R$cor_uncond,na.rm=TRUE), "/", nrow(R), "\n")
cat("dIR park>uncond (창 다름 — 비교 아님, 기술통계):", sum(R$dIR_park>R$dIR_uncond,na.rm=TRUE), "/", nrow(R), "\n")
cat("\nbest_dIR:", q(R$best_dIR), " best_arm:\n"); print(R[,.N,by=best_arm]); print(R[,.N,by=best_w])
cat("survivors (best_dIR>=0.05):", sum(R$best_dIR>=0.05,na.rm=TRUE), "\n")
cat("any positive best_dIR:", sum(R$best_dIR>0,na.rm=TRUE), "\n")
cat("beat-weight counts uncond:", sum(R$n_beat_weights_uncond), " park:", sum(R$n_beat_weights_park), "\n")

## 요구조건 지도 (해석해): 최소 슬리브 IR = solve for dIR>=0.05 at given rho, w
req_ir <- function(rho, w = 0.20, ir_i = NULL) {
  # book active = (1-w)a_i + w a_s ; IR_book = ((1-w)mu_i + w mu_s)/sd(...) * sqrt(12)
  # incumbent overlap IR 사용, sd 정규화: a_i ~ (mu_i, s_i), a_s ~ (mu_s, s_s)
  NULL
}
## 수치해: incumbent 창내 IR·sd 를 1 로 정규화(IR 은 스케일 불변) → 슬리브 sd 도 1 로 두고 IR_s 를 구함
solve_req <- function(rho, ir_i, w = 0.20, target = 0.05) {
  f <- function(irs) {
    num <- (1-w)*ir_i + w*irs
    den <- sqrt((1-w)^2 + w^2 + 2*w*(1-w)*rho)
    num/den - ir_i - target
  }
  tryCatch(uniroot(f, c(-20, 20))$root, error = function(e) NA_real_)
}
R[, req_ir_uncond := mapply(solve_req, cor_uncond, ir_inc_overlap_uncond, MoreArgs = list(w=0.20))]
R[, req_ir_park   := mapply(solve_req, cor_park,   ir_inc_overlap_park,   MoreArgs = list(w=0.20))]
R[, short_uncond := req_ir_uncond - ir_uncond]
R[, short_park   := req_ir_park   - ir_park]
cat("\nrequired IR (w=0.20) uncond:", q(R$req_ir_uncond), " park:", q(R$req_ir_park), "\n")
cat("shortfall uncond:", q(R$short_uncond), " park:", q(R$short_park), "\n")
L <- rbindlist(list(
  R[, .(factor, arm="uncond", cor=cor_uncond, ir=ir_uncond, dIR=dIR_uncond, req=req_ir_uncond, short=short_uncond, best_dIR)],
  R[, .(factor, arm="parked", cor=cor_park,   ir=ir_park,   dIR=dIR_park,   req=req_ir_park,   short=short_park, best_dIR)]))
cat("\n== top5 closest (min shortfall) ==\n")
print(L[order(short)][1:5], digits=4)
cat("\n== top5 by best_dIR ==\n")
print(R[order(-best_dIR)][1:5, .(factor, best_arm, best_w, best_dIR, cor_uncond, ir_uncond, cor_park, ir_park)], digits=4)
fwrite(R, "stage_artifacts/pg2_hunt/shard0_results_enriched.csv")
cat("\n=== FULL CSV ===\n")
out <- R[, .(factor, n, cor_uncond=round(cor_uncond,4), ir_uncond=round(ir_uncond,4), dIR_uncond=round(dIR_uncond,4),
             cor_park=round(cor_park,4), ir_park=round(ir_park,4), dIR_park=round(dIR_park,4),
             best_arm, best_dIR=round(best_dIR,4), best_w)]
setorder(out, -best_dIR)
cat(paste(capture.output(fwrite(out, stdout())), collapse="\n"), "\n")
