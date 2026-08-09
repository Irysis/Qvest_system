#!/usr/bin/env Rscript
# fq002b_verdict_collect_20260809.R — FQ-002 (B) 판정 수집 + next_probe 등재.
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
i <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-002"), logical(1)))
stopifnot(length(i) == 1L)
ids <- vapply(Q$entries, function(x) as.character(x$id %||% ""), character(1))
nxt <- max(as.integer(sub("^FQ-0*", "", grep("^FQ-[0-9]+$", ids, value = TRUE))), na.rm = TRUE)

Q$entries[[i]]$status <- "two_consumption_surfaces_closed_material_specific_negative"
Q$entries[[i]]$verdict_b_20260809 <- paste0(
  "★(B) 배제형 필터 소비면 = **사전등록 F1 반증**. 창 79개월(2020-01~2026-07, PIT lag 적용) · ",
  "커버 24.0%(4.80종/20) · 월평균 제외 1.29종. 기준선 book IR 1.0950/PORT_t 2.768 → ",
  "하위3분위 제외 IR 0.9696(**ΔIR -0.1255**)/PORT_t 2.451. ",
  "음성대조(난수 30 draw) q95 +0.0537 **이하** → 신호 아님. 회수율 **-30.3%**(천장 대비 반대 방향). ",
  "★통제 전부 작동: 양성대조 완전예지 +0.4153(사전 +0.4139 재현) · 음성대조 중앙 -0.0804(무작위 제외 자체가 해로움) · ",
  "시대 분할 전반 -0.0845/후반 -0.1437 부호 일치(교락 아님). ",
  "⇒ 랭킹(PORT_t 0.51)과 필터(ΔIR -0.126) 두 소비면 모두 닫힘. ",
  "★★단 **천장은 실재**(+0.4153) — 커버 집합에 큰 분산이 있는데 w_ratio 가 못 짚는다. **재료-특이** negative.")
Q$entries[[i]]$next_action <- paste0(
  "▶(A) 전구간 크롤 지불은 **EV 크게 하락** — 두 소비면이 닫힌 재료에 1.5~3.2일 지불 근거 약함. 보류. ",
  "▶남은 축 = FQ-", sprintf("%03d", nxt + 1), " (같은 천장, 다른 계약 필드). 그것이 천장 25% 이상 회수 시 (A) 재검토.")
Q$entries[[i]]$l_code <- "L-AR-20260809_223000"

new <- list(
  id = sprintf("FQ-%03d", nxt + 1),
  lane = "non_return",
  title = "계약 커버 집합의 천장(+0.4153)을 다른 필드로 겨냥 — n_contracts / amend_n / round_n / fx_n",
  status = "frontier_open",
  owner = "Q-Lead (FQ-002 (B) next_probe, 2026-08-09)",
  hypothesis = paste0(
    "계약-커버 종목 집합 안에 **큰 실현수익 분산**이 있다(완전예지 1종 제외로 ΔIR +0.4153). ",
    "w_ratio(금액/매출)는 그것을 못 짚었고 필터에서 부호가 반대였다. ",
    "천장은 **재료 무관하게 커버 집합의 성질**이므로, 다른 계약 필드가 같은 표적을 짚는지는 미검이다."),
  ev_rationale = paste0(
    "천장 +0.4153 이 게이트(0.05)와 무작위 q95(+0.054)를 크게 넘는다 — 표적이 실재한다는 실측. ",
    "데이터 이미 보유(panelx_B_corrected 의 n_contracts/amend_n/round_n/fx_n, 추가 크롤 0). ",
    "★갈아타기 아님: 같은 표적(커버 집합 분산)에 대한 **다른 신호**이고, w_ratio 는 사전등록 F1 으로 이미 판정 종료됐다."),
  next_action = paste0(
    "①필드별 사전등록 1회씩(형태 고정: 하위 3분위 제외, 강도 k≈1) — **필드를 흔들어 최선을 고르면 sweep** 이므로 ",
    "각 필드 독립 사전등록 + 음성대조/양성대조 동반. ②판정 기준은 게이트가 아니라 **무작위 q95**. ",
    "③회수율(ΔIR / 0.4153) 병기. ④F3 시대 분할 필수(겹침이 2020 11% → 2026 36% 추세)."),
  wall_check = "천장 실측 +0.4153(k=1) · 무작위 q95 +0.0537 · 기준선 book PORT_t 2.768(계약 창 79개월 — 전체 271개월 6.18 대비 불리한 창, 인용 시 병기)",
  created = "2026-08-09")

Q$entries <- c(Q$entries, list(new))
Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("판정 수집 완료 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
cat(sprintf("  FQ-002 status → %s\n", Q$entries[[i]]$status))
cat(sprintf("  신규 %s [%s]\n", new$id, substr(new$title, 1, 70)))
