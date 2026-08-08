p <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json"
x <- readLines(p, warn = FALSE)
cat(sprintf("file lines = %d  (positive control: nonzero expected)\n", length(x)))
pats <- c("0.765", "0.979", "0.709", "0.889", "12.71", "19.88",
          "monotonicity 0.25", "13.1", "8.0", "ZZZ_SHOULD_BE_ZERO")
for (pat in pats) {
  hit <- grep(pat, x, fixed = TRUE)
  cat(sprintf("PATTERN %-20s -> %d hit(s) lines: %s\n", pat, length(hit),
              paste(hit, collapse = ",")))
}
