#!/usr/bin/env Rscript
# fq_append_depth_20260809.R — regime chain step 4 산출을 프론티어 큐에 등재 (정본 writer 경유).
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(x) as.character(x$id %||% ""), character(1))
nxt <- max(as.integer(sub("^FQ-0*", "", grep("^FQ-[0-9]+$", ids, value = TRUE))), na.rm = TRUE)
cat(sprintf("현 항목 %d · 최대 FQ %d\n", length(Q$entries), nxt))

mk <- function(k, title, status, ev, next_action, adj = NULL) {
  e <- list(id = sprintf("FQ-%03d", nxt + k), title = title, status = status,
            owner = "Q-Lead (regime chain step4, 2026-08-09)",
            ev_rationale = ev, next_action = next_action,
            wall_check = "271개월 · 캐리어 STR_1715_on_M4gAE_R05_noLayer4_PG2 · 커버리지 OK(북 최신월 동기)",
            created = "2026-08-09")
  if (!is.null(adj)) e$adjacency_note <- adj
  e
}

new1 <- mk(1,
  "오버레이 노출 깊이 축 — 방어는 floor 0.80까지 평평, IR 대가만 단조 감소",
  "measured_open",
  paste0("반응면 실측(271개월, ×book): ΔMDD 가 floor 0.00~0.80 구간 내내 +0.0207 로 불변이고 0.90 에서야 +0.0174 로 처음 하락. ",
         "ΔIR 은 -0.473 → -0.247(0.80) → -0.121(0.90) → -0.058(0.95) 로 단조 개선. ",
         "⇒ 노출 0.387 까지 내려가던 깊은 축소는 **전부 순수 IR 손실**이고 방어는 얕은 축소에서 전량 나온다. ",
         "fire_2006 은 floor<1.00 전 구간 1.000(절대 문턱이라 구속 낙폭 구간을 항상 포착 — 발화율 제약형은 0/6)."),
  paste0("★값 선택은 아직 안 했다(argmax 미수행, not_a_selection 라벨). floor 를 고르려면 IR/MDD 교환비 판정 기준을 먼저 사전등록해야 하고 ",
         "그 순간 selection → DSR>=0.5 HARD 게이트 대상. 후보 기준 = Calmar(§3 HARD 0.64 기존) 또는 book-marginal ΔCalmar. ",
         "선행 조건 = FQ-{nxt+2} (게이트 정합) 판단. 반응면 산출물: stage_artifacts/paper_recharge/depth_response_surface_20260809.json"),
  NULL)

new2 <- mk(2,
  "regime 레인 게이트가 MDD 개선을 안 본다 — ΔIR 단독 판정과 '오버레이=MDD 레버' 실측의 불일치",
  "dohoon_decision",
  paste0("오늘 3라운드가 모두 같은 것을 실측: bare IR 1.465(MDD -40.7%) vs book_L5 IR 1.433(MDD -23.3%) — ",
         "오버레이는 IR 을 지불하고 낙폭을 산다. 그런데 regime/optimizer 레인 판정은 ΔIR>=0.05 **단독**이라 ",
         "ΔMDD +0.0207 을 내는 후보도 '레버 아님'으로 채택 0 이 된다. 게이트가 레버의 축을 안 본다."),
  paste0("★도훈 판단: §2/§3 에 ΔCalmar(또는 ΔMDD) 병행 판정을 추가할지. ",
         "추가 시 기존 HARD 3종(PORT_t 2.95 · oos_retention 0.7 · calmar 0.64)과의 관계 정의 필요 — ",
         "완화가 아니라 **축 추가**여야 한다(measurement-graduation 문턱 완화 금지 원칙). ",
         "미결 동안 FQ-{nxt+1} 의 값 선택은 보류."),
  NULL)

new3 <- mk(3,
  "발화율 제약 프레임의 적용 조건 — 신호 정상성 전제 + 절대 문턱 신호 부적용",
  "settled_negative_scoped",
  paste0("chain step2/3 실측: 확장창 분위 문턱은 **신호의 정상성에 의존**한다. Hurst(상대적 정상)는 발화율 31.8% vs 목표 30.1% 보존, ",
         "vol(군집성·비정상)은 8.1% 로 붕괴 → rolling 분위로 수리 후 27.5%. ",
         "그리고 발화율을 맞춘 vol 팔은 구속 낙폭 구간 0/6 인데 절대 문턱 voltgt 는 6/6 — ",
         "voltgt 의 방어는 절대 문턱에서 오지 상대 분위에서 오지 않는다(상대화하면 신호가 바뀐다)."),
  paste0("소비: ①발화율 계약·분모 계약을 wrap_exposure_adapter 로 승격 완료(래퍼가 ±5%p 강제, eligible_from 로 분모 명시) ",
         "②신규 exposure 어댑터 설계 시 '이 신호가 정상적인가'를 먼저 물을 것 ",
         "③절대-문턱 신호에는 발화율 제약 프레임을 적용하지 말 것(깊이 축으로 갈 것 = FQ-{nxt+1})"),
  NULL)

new4 <- mk(4,
  "Hurst 시장 레짐 타이밍 — long-only 방어 전용 불가 (chain step1/2 negative)",
  "settled_negative_scoped",
  paste0("고정문턱 H>0.5 는 271개월 중 240개월(88.6%) 발화해 bare 로 수렴(ΔMDD = bare 와 소수4자리 동일). ",
         "발화율을 30%로 묶어도 ΔMDD -0.1746(악화)이고 GFC 0/9 · 2006 구속구간 0/6 발화. ",
         "⚠ 방향-조건부 검정(np1b)은 **양성 대조 3/3 실패**로 기전('하락도 추세다')을 확증하지 못했다 — 가설 상태."),
  paste0("부활 조건(INV-7): ①숏 허용 프레임(현 제약 밖) ②방향-조건부 변형(H × 수익부호)이 낙폭 정렬을 실증 ",
         "③일별 리밸 프레임. 미측정 소비면: monitoring 신호(배분 라벨 실패와 별개 축) · β예산."),
  "FQ-095(dohoon_confirm_required) 와 인접: 그쪽은 '신호 1건의 MDD 구제'가 D2-killed 셀과 같은지의 판정 대기. 본 항목은 특정 신호(Hurst)의 실측 negative 라 별개이나, FQ-095 판정 결과에 따라 소비 경로가 달라질 수 있음.")

Q$entries <- c(Q$entries, list(new1, new2, new3, new4))
Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("등재 완료 — added=%d · removed=%d · 총 %d\n", res$added, res$removed, res$n))
for (e in list(new1, new2, new3, new4)) cat(sprintf("  %s [%s] %s\n", e$id, e$status, substr(e$title, 1, 78)))
