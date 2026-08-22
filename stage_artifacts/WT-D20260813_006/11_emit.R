## WT-D20260813_006 / FQ-234 — alpha_vector 발행 (terminal_form = alpha_vector, 사전등록)
## null 라운드여도 발행한다: 다음 라운드가 같은 다리(패널·PIT 배관·통제)를 재사용한다.
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
P <- as.data.table(read_parquet(file.path(OUT,"absorb_panel.parquet"))); P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT,"fwd.rds"))
RET <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
vs <- sort(unique(RET$Date)); vs <- vs[vs < as.Date("2026-06-01")]
A <- readRDS(file.path(OUT,"alpha_variants.rds"))
S <- merge(A$primary[Date %in% vs][, .(Date, Ticker, alpha_score = score)],
           A$absorb_neu[Date %in% vs][, .(Date, Ticker, alpha_score_neu = score)],
           by = c("Date","Ticker"), all.x = TRUE)
S <- merge(S, P[, .(Date, Ticker, absorb_raw = absorb, win_vol, log_size)], by = c("Date","Ticker"), all.x = TRUE)
S[, metric_type := "canonical_screen"]
S[, spec_id := "FQ234_absorb_w3_corr"]
S[, direction_note := "alpha_score = z(-absorb): 사전등록 방향(흡수 강도 낮은 종목 선호). 실측은 이 방향을 지지하지 않음 — 부호 반전 금지(C13), 재사용 시 신규 사전등록 필요."]
write_parquet(S, file.path(OUT, "alpha_scores.parquet"))
cat("rows:", nrow(S), " months:", uniqueN(S$Date), " tickers:", uniqueN(S$Ticker), "\n")
cat("date range:", as.character(min(S$Date)), as.character(max(S$Date)), "\n")
