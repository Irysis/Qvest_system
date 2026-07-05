ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
suppressMessages({ library(data.table); library(xts) })
ppy <- 12
ym <- function(d) format(as.Date(d), "%Y-%m")

# book active (authoritative noLayer4)
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
pr <- as.data.table(bt$period_returns)[, .(date, ret_net)]
br <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
book <- merge(pr, br, by="date"); setorder(book, date)
book <- book[date <= as.Date("2026-06-30")]
book[, ym := ym(date)]; book[, book_active := ret_net - benchmark_ret]
book[, pos := .I]

# FULL sleeve (256 contiguous months) — proper dense offset test
q07 <- as.data.table(readRDS("stage_artifacts/frontier_a_quality_q07/qual_q07_active.rds"))
setnames(q07, "active", "sleeve_active"); q07[, ym := ym(Date)]; setorder(q07, Date)

# join full sleeve onto book by ym
m <- merge(book[, .(ym, pos, book_active)], q07[, .(ym, sleeve_active)], by="ym", all.x=TRUE)
setorder(m, pos)
cat(sprintf("[full-sleeve] book months=%d, sleeve non-NA overlap=%d\n", nrow(m), sum(!is.na(m$sleeve_active))))

# offset scan on DENSE overlap: shift sleeve by k book-positions
mm <- m[!is.na(sleeve_active)]
offs <- -3:3
sc <- sapply(offs, function(k){
  tgt <- book[match(mm$pos + k, pos), book_active]
  ok <- is.finite(tgt) & is.finite(mm$sleeve_active)
  if (sum(ok) < 20) return(NA_real_)
  stats::cor(mm$sleeve_active[ok], tgt[ok])
})
names(sc) <- as.character(offs)
cat("[full-sleeve DENSE] offset -3..+3 cor(sleeve_full, book_active):\n"); print(round(sc,4))
cat(sprintf("[full-sleeve DENSE] max|cor| at offset = %s\n", offs[which.max(abs(replace(sc,is.na(sc),-Inf)))]))

# Also: does the sleeve month-start ym exactly equal book ym? show first/last overlaps
cat("\n[ym match] first 5 book ym vs whether sleeve has that ym:\n")
print(head(m[, .(ym, has_sleeve = !is.na(sleeve_active))], 8))
cat("\n[caution ym vs book ym exact?] caution sleeve months:\n")
cau <- as.data.table(readRDS("stage_artifacts/frontier_a_quality_q07/qual_caution_active.rds"))
cau[, ym := ym(Date)]
print(merge(cau[,.(ym, caution_active=active)], book[,.(ym, book_active)], by="ym", all.x=TRUE))
