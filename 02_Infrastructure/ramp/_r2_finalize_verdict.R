## _r2_finalize_verdict.R — R2 최종 verdict 교정: raw PORT_t PASS를 graduation HARD로 재판정.
## any_pass_portt (raw) vs any_grad_pass (자본급 3게이트). 후자만 결론 뒤집기 자격.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(1)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
SL <- as.data.table(read_parquet(file.path(OUT,"r2_topn_sleeve_gates.parquet")))
ST <- as.data.table(read_parquet(file.path(OUT,"r2_topn_gates.parquet")))
GATE_PT <- 2.95; GATE_OOS <- 0.7; GATE_CAL <- 0.64

allc <- rbind(SL[,.(top_n,model,port_t_capwt,oos_retention,calmar)],
              ST[,.(top_n,model,port_t_capwt,oos_retention,calmar)], fill=TRUE)
allc[, portt_pass := is.finite(port_t_capwt) & port_t_capwt>=GATE_PT]
allc[, grad_pass := portt_pass & is.finite(oos_retention) & oos_retention>=GATE_OOS &
                    is.finite(calmar) & calmar>=GATE_CAL]
# stack_EW_topNsel = selection-operator (구성이 N별로 max-pick) → 오염 라벨
allc[, selection_contaminated := model=="stack_EW_topNsel"]

raw_portt_pass <- allc[portt_pass==TRUE]
grad_pass <- allc[grad_pass==TRUE]
cat("=== raw PORT_t>=2.95 (진단) ===\n"); print(raw_portt_pass)
cat("\n=== graduation HARD 3종 통과 (자본급) ===\n")
if(nrow(grad_pass)) print(grad_pass) else cat("  (0건)\n")

verdict <- list(
  n_grid = c(15L,20L,25L), cost_bps_oneway = 15,
  gate = list(port_t=GATE_PT, oos_retention=GATE_OOS, calmar=GATE_CAL),
  raw_portt_pass = raw_portt_pass,
  raw_portt_pass_count = nrow(raw_portt_pass),
  grad_pass = if(nrow(grad_pass)) grad_pass else data.table(),
  grad_pass_count = nrow(grad_pass),
  selection_contamination_note = "stack_EW_topNsel = in-sample top-4 argmax (selection operator); N20 3.54는 sweep-max 재보고. 구성고정 R1fixed N20=2.59.",
  verdict = if(nrow(grad_pass)>0) "POSITIVE_capital_grade" else "NEGATIVE_unchanged",
  verdict_text = if(nrow(grad_pass)>0)
      "top-N 민감도로 자본급 survivor 발견 — 결론 뒤집힘" else
      "raw PORT_t는 N15 Consensus(3.18)/N20 topNsel(3.54) 2건 초과하나 oos_retention·calmar HARD 전부 미달 + topNsel은 선택연산자 오염 → 자본급 0건. R1 음성 결론(직교≠수익, sleeve-레벨) 불변. top-N 민감도로 결론 안 뒤집힘.",
  best_sleeve_by_N = SL[, .SD[which.max(port_t_capwt)], by=top_n][,.(top_n, model, port_t_capwt, oos_retention, calmar)],
  best_stack_by_N  = ST[, .SD[which.max(port_t_capwt)], by=top_n][,.(top_n, model, port_t_capwt, oos_retention, calmar, stack_fams)],
  challenge_note = ".cache/_ramp_r2_challenge_note_20260705.md",
  vintage_pin = "session_2026-07-05"
)
write_json(verdict, file.path(OUT, sprintf("r2_topn_verdict_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
cat(sprintf("\nVERDICT_FINAL: %s (raw_portt_pass=%d, grad_pass=%d)\n",
    verdict$verdict, nrow(raw_portt_pass), nrow(grad_pass)))
