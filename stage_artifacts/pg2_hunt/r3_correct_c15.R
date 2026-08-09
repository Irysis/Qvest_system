## r3 — FQ-213 정정: STR_1675 계열이 계약 경로 밖(C15 우회 + 10-component 부재)
## ★AX-002 는 통계보다 상위다 — 적대 검증 4축을 통과해도 하네스 밖 성과는 유효하지 않다.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[r3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

CORR <- paste0(
  "★★★정정(2026-08-09 r2/r3 실측): 이 후보는 **계약 경로 밖 재료**다. 통계 결과는 유효하나 자본 승격 불가. ",
  "①**C15 우회** — 두 전략 모두 `run_all.R:49` `DAILY_DB_DIR <- .cache/factor_db_daily` + ",
  "`:131` `ds_daily <- open_dataset(pq_files)` 로 **Factor DB parquet 을 직접 연다**. ",
  "`load_month_factors()` 호출 **0건**(두 파일 전수 grep). ",
  "★그런데 헤더 `:22` 가 이것을 **'C15 : 일간 DB Arrow open_dataset 직접' 이라며 'PIT 준수' 절에 적어뒀다** — ",
  "규칙이 **금지하는 행위를 준수로 라벨**한 것이다. ML daily parquet carve-out 은 '명시 승인 hypothesis만' 조건부인데 ",
  "승인 기록을 찾지 못했다. ",
  "②**계약 10-component 부재** — 산출물이 `nav_*.csv` + `ic_timeseries.csv` + PNG 뿐이고 ",
  "`build_bt_result`/`audit_bt_result` 흔적이 없다(감사·계보 산출물 **0건**). 계약 용어로 `metric_type = unavailable`. ",
  "③**AX-002** — '하네스 내 성과만 유효. 프로세스 우회 = 미래참조 = C1 위반 동급'. ",
  "적대 검증 4축(무작위 파킹 97% · 귀무 창 **2.5%** · 연도 7/7 · 중복 아님)은 **내가 계산한 통계**이고 ",
  "재료 자체가 하네스를 안 거쳤다. AX-002 가 상위다. ",
  "★부수 확인: 두 전략은 파일명이 같지만(`nav_QRebal_B.csv`) **서로 다른 산출물**이다 ",
  "(크기 204,602 vs 212,556 · 시작 2008-04-03 vs 2008-02-05) — 내 '동일 파일' 의심은 철회. ",
  "★이 계통은 이미 기록돼 있다: [[project-c15-bypass-gate-tolerance-20260808]] ",
  "'C15 우회 = 게이트가 두 겹으로 눈감음'. 오늘은 **후보를 승격시킬 뻔한 자리**에서 다시 만났다. ",
  "⇒ 선결 조건: ⓐC15 carve-out 승인 여부(도훈 판단) ⓑ계약 경로 재산출(build_bt_result + audit) ",
  "ⓒ재산출 값과 현 NAV 의 parity 확인. 셋 다 통과하기 전까지 **screen-tier 라벨 유지**.")

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
hit <- 0L
for (k in seq_along(Q$entries)) {
  if (ids[k] %in% c("FQ-212","FQ-213")) {
    Q$entries[[k]]$next_action <- paste0(as.character(Q$entries[[k]]$next_action)[1], " ", CORR)
    if (ids[k] == "FQ-213") Q$entries[[k]]$status <- "screen_tier_contract_path_required"
    hit <- hit + 1L; say("정정 기입 %s%s", ids[k],
      if (ids[k]=="FQ-213") " (status → screen_tier_contract_path_required)" else "")
  }
}
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d항목 · 정정 %d건", length(read_frontier_queue()$entries), hit)

## 병목 지도 v60
mp <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(mp, "raw", file.size(mp)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v59 ("
if (length(gregexpr(anchor, txt, fixed=TRUE)[[1]]) == 1L) {
  ins <- paste0(
    "**갱신**: 2026-08-09 v60 (★**전략 풀 라운드 — 후보 발생·그러나 계약 경로 밖**[pg2_hunt s1~r3]. ",
    "①표적을 'IR 0.7+ 재료' 로 확정하고 팩터가 아닌 **완성 전략 풀**을 처음 book-marginal 로 측정 ",
    "(파일 1,052 → 계열 52 → 중복 18쌍 제거 → **유효 독립 40**). ",
    "②무처리 1급 통과 0 · **cor(rho, IR) = +0.712** — 331 라운드 구조 재현(높은 IR 은 높은 상관과 함께 온다). ",
    "③★**파킹 레버가 전략 풀에서 훨씬 강하다** — rho +0.225 → **−0.005**(인하 12/12), ",
    "팩터 슬리브 바닥 0.32 를 넘어 **음의 상관**까지. 부족분 +0.636 → +0.164 ⇒ **1급 3/12**. ",
    "④★적대 4축에서 STR_1675 두 변형 전건 통과 — 무작위 파킹 **97.0%** · **귀무 창 2.5%**(계약 슬리브는 14.8% 로 탈락한 관문) · 연도 7/7. ",
    "⑤★★**그러나 재료가 계약 경로 밖**: `run_all.R` 이 `open_dataset(.cache/factor_db_daily)` 로 **C15 우회**하고 ",
    "`load_month_factors()` 호출 0건인데 헤더는 이를 **'PIT 준수' 로 라벨**. 계약 10-component·audit **0건**. ",
    "⇒ **AX-002 가 통계보다 상위** — 자본 승격 불가, screen-tier 유지. 선결 = C15 carve-out 승인(도훈) + 계약 재산출 + parity. ",
    "⑥CI 기준은 애초에 0/12(73개월에서 문턱 0.05 는 se ~0.093). ",
    "⑦커버리지 census: 파킹 적용 가능 39/40, 불가 1건 = STR_1698(2024-04 종료, 무처리 부족분 **0.087** 로 최고였음, 칩 task_b065b34d). ",
    "상세 = `stage_artifacts/pg2_hunt/s8_parked.csv` · `s9_adversarial.R`) | ")
  txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
  ob <- charToRaw(enc2utf8(txt2)); writeBin(ob, mp)
  r2 <- readBin(mp, "raw", file.size(mp))
  say("지도 v60: %d → %d바이트 · CR %d(원 %d) · v60 %s · v59 보존 %s",
      length(raw), length(ob), sum(r2==as.raw(13)), sum(raw==as.raw(13)),
      grepl("v60", rawToChar(r2), fixed=TRUE), grepl("v59 (", rawToChar(r2), fixed=TRUE))
} else say("★지도 앵커 불일치")
say("=== r3 완료 ===")
