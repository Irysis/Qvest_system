#!/usr/bin/env Rscript
## P4C02 걸음 열기 진입점 양성 대조(변경분 점검 R-2 (a) · 재점검 R-5 · DESIGN_draft §4 절차 2) — 실제 사슬에서 정책 밖 걸음 다섯을 열어 보고 모두 정책 사유로
##   거부되는지 본다. 거부되는 열기는 원장에 아무것도 쓰지 않는다(rc_p4_step_open 은 검사 전부를 지난 뒤에만 .rcp4_append) — 원장 md5 · 줄 수 전후 대조로 확인한다.
##   조건: tick_hold 가 있을 때만(무인 틱과 겹치지 않게) · 대조 칸 사양은 사슬 디렉터리 밖(인자 = 빈 스크래치 폴더) · 측정 · 생성기 호출 없음 · 성과 값 없음.
##   정상 대조(기저 + 성장)는 열지 않는다(열면 원장에 걸음 1 이 생긴다) — 같은 검사 함수(rc_p4_spec_diff · .rcp4_step_policy_why)로 사유 0 을 본다.
##   산출: results/step_policy_entry_controls.json(대조마다 거부 여부 · 정책 사유 · 그 밖 사유)
## 실행(저장소 루트): Rscript 04_Research/programs/P4_ASSEMBLY/P4C02_fc_blend/tools/entry_controls.R <스크래치 빈 폴더>
suppressMessages(source("04_Research/programs/_lib/round_core/v5/load.R"))
stopifnot(identical(RC_VERSION, "v5"))
root <- rc_root(); cd <- file.path(root, "04_Research/programs/P4_ASSEMBLY/P4C02_fc_blend")
if (!file.exists(file.path(cd, "tick_hold"))) stop("[entry_controls] tick_hold 가 없다 — 무인 틱과 겹칠 수 있어 하지 않는다")
sd <- commandArgs(TRUE)[1]; if (is.na(sd)) stop("인자: <스크래치 빈 폴더>")
if (startsWith(tolower(gsub("\\\\", "/", sd)), tolower(gsub("\\\\", "/", cd)))) stop("대조 칸 사양은 사슬 디렉터리 밖에")
dir.create(sd, recursive = TRUE, showWarnings = FALSE)
led <- file.path(cd, "chain_steps.jsonl"); m0 <- rc_md5(led); n0 <- length(readLines(led, warn = FALSE))
pool <- rc_p4_base_pool(root); sp <- rc_json_read(file.path(cd, "chain_spec.json"))
bcs <- rc_json_read(file.path(cd, "base_cell_spec.json"))
E <- function(nm) sprintf("04_Research/strategies/%s/engine.R", nm)
mk <- function(nm, f) { s <- f(bcs); p <- file.path(sd, paste0(nm, ".json")); rc_json_write(s, p); p }
CT <- list(
  list(id = "block_weighting", block = "weighting", expect = "정책 밖 블록",
       cell = mk("block_weighting", function(s) { s$weighting <- list(kind = "score"); s })),
  list(id = "axis_factors", block = "blend", expect = "칸 사양 축: factors",
       cell = mk("axis_factors", function(s) { s$factors <- list(list(id = "D02_Beta", direction = "defensive")); s })),
  list(id = "part_icw", block = "blend", expect = "정책 밖 엔진(part_engine_rx)",
       cell = mk("part_icw", function(s) { s$base_signal <- list(kind = "engine_blend", paths = list(E("FC_FAM_value"), E("FC_FAM_consensus_ICW"))); s })),
  list(id = "blend_drop_base", block = "blend", expect = "부모 칸 엔진을 뺐다",
       cell = mk("blend_drop_base", function(s) { s$base_signal <- list(kind = "engine_blend", paths = list(E("FC_FAM_growth"), E("FC_FAM_consensus"))); s })),
  list(id = "blend_two_parts", block = "blend", expect = "새 부품 = 2개",
       cell = mk("blend_two_parts", function(s) { s$base_signal <- list(kind = "engine_blend", paths = list(E("FC_FAM_value"), E("FC_FAM_growth"), E("FC_FAM_consensus"))); s })))
H <- "대조 걸음 — 걸음 정책 밖 칸이 걸음 열기에서 거부되는지 본다(측정 없음)"; M <- "걸음 정책 진입점 양성 대조 · 거부되면 원장 무기록"
out <- lapply(CT, function(x) {
  e <- tryCatch({ rc_p4_step_open(cd, 1L, H, M, x$block, x$cell, 0L, sp$generator$id, root = root, pool = pool); "OPENED" }, error = function(e) conditionMessage(e))
  rs <- trimws(sub("^- ", "", strsplit(e, "\n", fixed = TRUE)[[1]][-1]))
  list(id = x$id, block = x$block, rejected = !identical(e, "OPENED"), expect = x$expect, policy_hit = any(grepl(x$expect, rs, fixed = TRUE)),
       policy_reasons = as.list(rs[grepl("걸음 정책", rs, fixed = TRUE)]), other_reasons = as.list(rs[!grepl("걸음 정책", rs, fixed = TRUE)]))
})
## 정상 대조(열지 않음) — 기저 + 성장: 칸 차이 ok · 정책 사유 0
okc <- mk("ok_value_growth", function(s) { s$base_signal <- list(kind = "engine_blend", paths = list(E("FC_FAM_value"), E("FC_FAM_growth"))); s })
dif <- rc_p4_spec_diff(bcs, rc_json_read(okc), "blend", root, pool)
pw <- .rcp4_step_policy_why(sp$step_policy, "blend", okc, root, changed = dif$changed, parent_csa = file.path(cd, "base_cell_spec.json"))
m1 <- rc_md5(led); n1 <- length(readLines(led, warn = FALSE))
res <- list(schema = "p4c02_entry_controls_v1", at = rc_now(), core = RC_VERSION, chain = sp$chain_id, spec_md5 = rc_md5(file.path(cd, "chain_spec.json")),
            controls = out, positive = list(id = "ok_value_growth", spec_diff_ok = isTRUE(dif$ok), changed = as.list(dif$changed), policy_reasons = as.list(pw), opened = FALSE),
            ledger = list(md5_before = m0, md5_after = m1, lines_before = n0, lines_after = n1, untouched = identical(m0, m1) && identical(n0, n1)))
dir.create(file.path(cd, "results"), showWarnings = FALSE); rc_json_write(res, file.path(cd, "results", "step_policy_entry_controls.json"))
for (o in out) cat(sprintf("[대조] %-16s 거부 %s · 정책 사유 일치 %s · 그 밖 사유 %d\n", o$id, o$rejected, o$policy_hit, length(o$other_reasons)))
cat(sprintf("[정상] ok_value_growth 칸 차이 ok %s · 바뀐 축 %s · 정책 사유 %d(열지 않음)\n", isTRUE(dif$ok), paste(dif$changed, collapse = ","), length(pw)))
cat(sprintf("[원장] 전후 md5 같음 %s · 줄 %d → %d\n", identical(m0, m1), n0, n1))
ok <- all(vapply(out, function(o) o$rejected && o$policy_hit, TRUE)) && isTRUE(dif$ok) && !length(pw) && identical(m0, m1)
quit(status = if (ok) 0L else 1L)
