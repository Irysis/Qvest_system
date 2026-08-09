## t1 — 수렴 기록 + 다음 표적(IR 0.7+ 재료) 후보 사전 확인
## 확정: 레버는 충분(파킹 rho −0.24 검증 · 필터 약한재료 +0.56)하나 **강한 재료를 더 강하게 하는 레버는 없다**.
##   필터는 근접군에 오히려 해롭다(IR −0.129 · 부족분 0.316→0.349).
## ⇒ 표적 = **출발 IR 0.7 이상 재료**. 팩터DB 최고 0.576, 계약 0.758 이 유일.
## ★다음 후보 = 팩터가 아니라 **완성된 전략 풀**(조립된 포트폴리오라 IR 이 높을 수 있고 book-marginal 미측정)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[t1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ops/frontier_queue_io.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

## ── 1. 원장 등재 ─────────────────────────────────────────────────────────────
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★★표적 확정 — 레버는 충분하고 **출발 IR 0.7+ 재료**가 유일한 병목",
  status = "frontier_open", owner = "UNCLAIMED — 다음 세션",
  claim = list(state="unclaimed", note="2026-08-09 PG2 아크가 표적을 이 형태로 확정"),
  ev_rationale = paste0("331 전수·합성·insider·필터·이식·결합 31라운드가 전부 통과 0 으로 끝났다. ",
    "무엇이 부족한지를 레버별로 분해해 병목을 하나로 좁혔다."),
  wall_check = paste0(
    "★요구조건: rho 0.24 에서 필요 IR **0.717** · rho 0.30 에서 **0.789**. ",
    "★레버 실측(전부 창 정합): ",
    "①**파킹** rho −0.236(창 정합 paired t **−5.448**, 26/30 · 창 효과 몫은 22%뿐) · IR +0.379 ",
    "②**유니버스 필터** rho −0.015(거의 무효) · IR **+0.560**(무작위 재료) / **−0.129**(근접군, 해롭다) ",
    "③**결합** rho −0.293 · IR +0.747(가산 예측 +0.939 대비 부분 상쇄). ",
    "★근접군 결합 실측: 부족분 중앙 0.316 → **0.349 악화**, 개선 3/8, V18_AM IR 0.576→0.433. ",
    "⇒ **강한 재료를 더 강하게 하는 레버는 하나도 없다**. 필터는 약한 재료 전용. ",
    "★재료 IR 실측: 팩터DB 최고 **0.576**(V18_AM 파킹) · 무작위 재료 −0.604 · insider 최고 0.222 · ",
    "**계약수주 0.758**(유일하게 필요치 초과). ⇒ 병목은 방법이 아니라 **출발 IR**."),
  next_action = paste0(
    "★next_probe(3) = ①**완성 전략 풀 측정** — 팩터가 아니라 조립된 포트폴리오(NAV)를 book-marginal 로 재라. ",
    "오늘 FR_002 가 명목 195 → **유효 독립 85** 로 센 폐지 풀 + `04_Research/strategies/` 178+ STR. ",
    "조립체는 팩터보다 IR 이 높을 수 있고 **book-marginal 로는 한 번도 안 쟀다**. ",
    "★착수 전 사전 확인 의무: NAV 커버리지·PG2 창 겹침·중복(오늘 폐지풀은 중복 55.5% 였다). ",
    "②**IR 0.7+ 재료의 존재 조건** — 계약이 왜 0.758 인지 분해(사건-구동? 희소성? 금액 magnitude?). ",
    "insider 도 사건-구동인데 0.222 였으므로 사건-구동은 답이 아니다. ",
    "③screen_route 재고 회수 — 오늘 메모리가 '소비자 0' 을 기록했다. 그 재고의 IR 분포부터 실측."),
  consumer_surfaces = c("알파 재료 발굴 우선순위", "book-marginal 후보 평가", "FQ 큐 우선순위",
    "폐지 풀·STR 재고 소비", "병목지도 재료 행"),
  revival_condition = "IR 0.7+ 재료가 발견되면 즉시 결합 레버 적용 — 레버는 이미 검증돼 있다",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

## ── 2. 다음 표적 사전 확인: 완성 전략 풀 ────────────────────────────────────
say("=== ★사전 확인: 완성 전략 NAV 자산 (착수 가부) ===")
inc <- bm_load_incumbent(); inc[, m := mi(date)]
cand <- unlist(lapply(c("04_Research/strategies", "06_Registry", ".cache", "qepm/registry"),
  function(r) if (dir.exists(r)) list.files(r, pattern="(nav|period_returns|returns).*\\.(csv|parquet|rds)$",
    recursive=TRUE, full.names=TRUE, ignore.case=TRUE) else character(0)))
cand <- unique(cand[file.size(cand) > 2000])
say("  NAV/수익 계열 후보 파일 **%d개**", length(cand))
if (!length(cand)) { say("  ★후보 0 — 스캔 패턴 재설계 필요(0을 결론으로 읽지 말 것)"); quit(status=0) }
say("  상위 디렉토리 분포:")
dd <- table(dirname(dirname(cand)))
print(head(sort(dd, decreasing=TRUE), 8))

say("=== 표본 12개 스키마·커버리지 실측 ===")
say("  %-46s %8s %8s %10s", "파일", "행", "개월", "PG2겹침")
okn <- 0L
for (f in head(cand[order(-file.size(cand))], 12)) {
  d <- tryCatch({ if (grepl("parquet$", f)) as.data.table(arrow::read_parquet(f))
    else if (grepl("rds$", f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
    else fread(f, nrows=50000) }, error=function(e) NULL)
  if (is.null(d) || !nrow(d)) next
  dc <- names(d)[which(tolower(names(d)) %in% c("date","period","ym"))[1]]
  if (is.na(dc)) next
  dv <- suppressWarnings(as.Date(as.character(d[[dc]]))); dv <- dv[!is.na(dv)]
  if (!length(dv)) next
  ov <- length(intersect(unique(mi(dv)), inc$m))
  say("  %-46s %8d %8d %10d", substr(basename(f),1,46), nrow(d), uniqueN(mi(dv)), ov)
  if (ov >= 60) okn <- okn + 1L
}
say("=== ★착수 판정 ===")
say("  PG2 겹침 60개월 이상 표본 내 **%d건**", okn)
say("  %s", if (okn >= 3)
  "★완성 전략 풀 측정 착수 가능 — 다음 라운드는 NAV 를 슬리브로 넣어 book-marginal 로 잰다" else
  "★표본에서 겹침 부족 — 전수 스캔으로 자산 위치를 먼저 확정해야 한다")
say("  ★규율: 착수 전 ①중복 제거(오늘 폐지풀 55.5%%) ②창 정합 ③subsample_null 게이트 적용")
say("=== t1 완료 ===")
