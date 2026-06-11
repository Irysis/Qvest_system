# _vfy_f3.R - band-rule state check (>=10 names to clear engine min-universe guard)
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/trackv_engine.R")
PASS <- function(lbl, ok, detail = "") cat(sprintf("[%s] %s %s\n", ifelse(ok, "PASS", "FAIL"), lbl, detail))
sd1 <- as.Date("2026-01-31"); sd2 <- as.Date("2026-02-28")
tk <- sprintf("T%02d", 1:12)   # T01=A, T02=B, T03=C, T04=D
jan <- c(12, 11, 5, 4, 3, 2.9, 2.8, 2.7, 2.6, 2.5, 2.4, 2.3)        # top2 = T01, T02
feb <- c(9, 12, 11, 10, 3, 2.9, 2.8, 2.7, 2.6, 2.5, 2.4, 2.3)       # ranks: T02=1, T03=2, T04=3, T01=4
S_band <- data.table(Date = rep(c(sd1, sd2), each = 12), Ticker = rep(tk, 2),
                     score = c(jan, feb), ret_ok = TRUE)
H <- tv_build_holdings(S_band, list(n_fixed = 2L, band = 3L))
jan_hold <- sort(H[Date == sd1, Ticker]); feb_hold <- sort(H[Date == sd2, Ticker])
PASS("F3a. Jan top-2 = {T01,T02}", identical(jan_hold, c("T01", "T02")), paste(jan_hold, collapse = ","))
PASS("F3b. band=3: incumbent T01 (rank4>3) out, T02 (rank1) kept, refill T03 (best non-held)",
     identical(feb_hold, c("T02", "T03")), paste(feb_hold, collapse = ","))
# control: without band, plain top-2 in Feb would be {T02,T03} too; show band differs when incumbent in band
feb2 <- c(10.5, 12, 11, 10, 3, 2.9, 2.8, 2.7, 2.6, 2.5, 2.4, 2.3)   # T01 rank3 <= band3 -> kept
S2b <- data.table(Date = rep(c(sd1, sd2), each = 12), Ticker = rep(tk, 2),
                  score = c(jan, feb2), ret_ok = TRUE)
H2 <- tv_build_holdings(S2b, list(n_fixed = 2L, band = 3L))
feb_hold2 <- sort(H2[Date == sd2, Ticker])
PASS("F3c. band=3: incumbents T01(rank3),T02(rank1) both within band -> kept (no refill)",
     identical(feb_hold2, c("T01", "T02")), paste(feb_hold2, collapse = ","))
cat("F3 DONE\n")
