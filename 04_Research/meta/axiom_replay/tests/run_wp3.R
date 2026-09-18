setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp3_knowledge_efficacy.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)

cat("=== ① dead config 조회의 변별력 ===\n")
pf <- wp3_preflight_events()
cat("  preflight_dead_precedent 이벤트:", nrow(pf), "\n")
cat("  이벤트 시각 범위:", format(min(pf$ts, na.rm = TRUE), "%m-%d"), "~",
    format(max(pf$ts, na.rm = TRUE), "%m-%d"), "\n")
pf <- wp3_join_attempts(pf, att)
hit <- pf$att_row[!is.na(pf$att_row)]
att$warned <- FALSE; att$warned[hit] <- TRUE
# 분모 — preflight 가 살아 있던 구간의 칸만
lo <- min(pf$ts, na.rm = TRUE)
win <- att[!is.na(att$opened_at) & att$opened_at >= lo, , drop = FALSE]
cat(sprintf("  그 구간 등록 칸 %d 중 경고 붙은 칸 %d (%.1f%%)\n",
            nrow(win), sum(win$warned), 100 * mean(win$warned)))
if (sum(!win$warned) > 0 && sum(win$warned) > 0) {
  a <- win$port_t[win$warned & win$measured]; b <- win$port_t[!win$warned & win$measured]
  cat(sprintf("  경고분 PORT_t 중앙 %.3f (n=%d) · 무경고분 %.3f (n=%d)\n",
              median(a, na.rm = TRUE), length(a), median(b, na.rm = TRUE), length(b)))
} else cat("  ★대조군이 없다 — 경고가 사실상 모든 칸에 뜬다. 변별력을 잴 수 없다.\n")

cat("\n=== ② §5.1 관찰 비교 — 교훈 주입 전후 ===\n")
# 09-04 부터 B1 LLM 설계 + 앞 논문 교훈 주입이 작동. 비교 지표는 첫 5칸 최고 PORT_t
res <- list()
for (i in seq_len(nrow(ent))) {
  s <- att[att$base_id == ent$base_id[i] & att$block %in% "B1", , drop = FALSE]
  if (!nrow(s)) next
  s <- s[order(s$n), ]
  f5 <- s[seq_len(min(5, nrow(s))), ]
  res[[length(res) + 1L]] <- data.frame(
    base_id = ent$base_id[i], regime = ent$regime[i], kind = ent$kind[i],
    n_b1 = nrow(s), first5_best = suppressWarnings(max(f5$port_t[f5$measured], na.rm = TRUE)),
    b1_best = suppressWarnings(max(s$port_t[s$measured], na.rm = TRUE)),
    f_frac = mean(s$grade %in% "F", na.rm = TRUE), stringsAsFactors = FALSE)
}
b1 <- do.call(rbind, res)
b1 <- b1[is.finite(b1$first5_best), ]
for (rg in c("pre_0904", "post_0904")) {
  s <- b1[b1$regime == rg, ]
  cat(sprintf("  %-9s n=%2d  첫5칸 최고 중앙 %.3f  B1칸수 중앙 %.0f  B1 내 F비율 %.2f\n",
              rg, nrow(s), median(s$first5_best), median(s$n_b1), mean(s$f_frac)))
}
set.seed(20260918)
x <- b1$first5_best[b1$regime == "pre_0904"]; y <- b1$first5_best[b1$regime == "post_0904"]
d0 <- median(y) - median(x)
bs <- replicate(4000, median(sample(y, length(y), TRUE)) - median(sample(x, length(x), TRUE)))
ci <- quantile(bs, c(.025, .975), na.rm = TRUE)
cat(sprintf("  중앙값 차(post-pre) = %+.3f  95%%CI [%+.3f, %+.3f] -> %s\n", d0, ci[1], ci[2],
            if (ci[1] > 0) "주입 후가 높다" else if (ci[2] < 0) "주입 후가 낮다" else "구분 불가"))
cat("  ★교락: 논문이 다르고 체제(커서·누적 규칙)도 같은 날 바뀌었다. 인과 아님.\n")

cat("\n=== ③ 공리의 행동 도달 ===\n")
root <- ar_root()
axf <- list.files(file.path(root, "qepm/memory/axioms/active"), pattern = "^AX-.*json$",
                  recursive = TRUE, full.names = TRUE)
cat("  활성 공리:", length(axf), "\n")
tab <- do.call(rbind, lapply(axf, function(f) {
  j <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j)) return(NULL)
  data.frame(id = j$axiom_id %||% j$memory_id %||% basename(f),
             mode = if (grepl("modes", f)) basename(dirname(f)) else "global",
             enforcement_mode = j$enforcement_mode %||% "-",
             status = j$status %||% "active", stringsAsFactors = FALSE)
}))
print(table(tab$enforcement_mode), row.names = FALSE)
cat("  ★enforcement_mode=documented 는 훅 차단 regex 없이 문서로만 존재한다(INV-2).\n")
cat("  ★즉 활성 공리 중 실행 경로에서 결정을 바꾸는 것은", sum(tab$enforcement_mode != "documented"), "건이다.\n")
saveRDS(list(preflight = pf, b1 = b1, axioms = tab), "out/wp3.rds")
