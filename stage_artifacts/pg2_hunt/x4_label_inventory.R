## x4 — x3 원장 기록 + 국면 라벨 후보 인벤토리 (이식 probe 착수 가부)
## ★설계 위험 선언: "재료별로 직교하는 국면을 찾는다" 는 **사후 선택 순환**이다.
##   ⇒ 라벨 후보를 **사전 고정**하고 (라벨 x 재료) 전 셀 보고. argmax 금지. 무작위 라벨 대조 필수.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

## ── 1. x3 원장 기록 ──────────────────────────────────────────────────────────
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)
nums <- suppressWarnings(as.integer(sub("^FQ-","",ids[grepl("^FQ-\\d+$", ids)])))
nid <- sprintf("FQ-%03d", max(nums, na.rm=TRUE)+1L)
Q$entries[[length(Q$entries)+1L]] <- list(
  id = nid,
  title = "★계약 유니버스는 실재 정보(B−C +0.349, 12/12, p<1e-4)이나 강한 재료는 못 올린다",
  status = "frontier_open", owner = "Q-Lead session 832fa2fc",
  claim = list(state="complete", session="832fa2fc", note="FQ-204 probe① 2026-08-09"),
  ev_rationale = paste0("x1 이 무작위 선별에서 유니버스 효과 +0.351 을 봤으나 **신호 기반 선별에도** ",
    "적용되는지, 그리고 '희소 유니버스' 효과와 구분되는지가 미검이었다."),
  wall_check = paste0("★3-arm(12재료 = 근접6+무작위6, 계약창 79개월 parked): ",
    "A 전체유니버스 / B 계약유니버스 필터 / C **같은크기(월평균 81종목) 무작위 유니버스**. ",
    "①B−A IR 중앙 **+0.065**(7/12, paired t +0.980 **p 0.348 비유의**) ",
    "②C−A IR 중앙 **−0.363**(개선 1/12) = 희소화 자체는 **해롭다** ",
    "③★계약 고유분 **B−C IR 중앙 +0.349 · 12/12 전건 · paired t +8.867 · p<1e-4** ",
    "⇒ '계약 공시를 낸 회사' 선별에 **실재 정보**가 있고 희소 유니버스 효과가 아니다. ",
    "x1 무작위 실측(+0.351)과 신호기반(+0.349)이 소수 3자리 일치. ",
    "★그러나 ⓐB arm 최고 ΔIR **+0.0135**(L11_Kyle_Lambda)로 문턱 0.05 미달 ",
    "ⓑ필터는 IR 만 올리고 **rho 는 거의 불변**(A 0.243~0.418 → B 0.218~0.366) ",
    "ⓒ근접군에서는 **오히려 악화**(B−A −0.048, V18_AM 0.576→0.433) vs 무작위군 +0.177 ",
    "⇒ 소비면은 **약한 재료의 구제**이지 강한 재료의 증폭이 아니다."),
  next_action = paste0("★next_probe(3) = ①**북 종목 필터 직접 측정** — PG2 보유를 계약-공시 종목으로 제한. ",
    "현재 `04_holdings.csv` 0행이라 불가(칩 task_be236d0c 선행). ",
    "②**IR 이득의 출처 분해** — 계약 공시 자체가 좋은 회사를 고르는가(퀄리티 대리), 아니면 ",
    "공시 시점의 정보인가. 공시 **이전 12개월** 유니버스로 같은 필터를 걸어 시점 성분 분리. ",
    "③약한 재료 구제 소비면 — B−A 이득이 무작위군(+0.177)에 집중되므로 ",
    "screen_route 탈락분을 계약 필터로 되살릴 수 있는지 전수 측정."),
  consumer_surfaces = c("북 종목 필터", "약한 재료 구제(screen_route 회수)", "유니버스 제약 설계", "book-marginal 후보"),
  revival_condition = "PG2 holdings 결손 수리 후 북 종목 직접 필터 측정 · 또는 rho 를 함께 낮추는 필터가 발견되면",
  created = "2026-08-09")
Q$updated <- "2026-08-09"; write_frontier_queue(Q)
say("원장 %d → %d · %s 등재", n0, length(read_frontier_queue()$entries), nid)

## ── 2. 국면 라벨 후보 인벤토리 ───────────────────────────────────────────────
say("=== 국면 라벨 후보 스캔 ===")
cand <- unlist(lapply(c(".cache","02_Infrastructure/regime","06_Registry","stage_artifacts"),
  function(r) if (dir.exists(r)) list.files(r, pattern="(regime|bear|vol|state|mrs).*\\.(parquet|rds|csv)$",
    recursive=TRUE, full.names=TRUE, ignore.case=TRUE) else character(0)))
cand <- unique(cand[file.size(cand) > 3000]); cand <- cand[order(-file.size(cand))]
say("  후보 파일 %d개", length(cand))
inc <- readRDS(file.path(OUT,"incumbent.rds")); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
say("  %-52s %8s %10s %8s %8s", "파일", "행", "개월", "PG2겹침", "이진라벨")
ok <- list()
for (f in head(cand, 14)) {
  d <- tryCatch({ if (grepl("parquet$",f)) as.data.table(read_parquet(f))
    else if (grepl("rds$",f)) { x <- readRDS(f); if (is.data.frame(x)) as.data.table(x) else NULL }
    else fread(f, nrows=100000) }, error=function(e) NULL)
  if (is.null(d) || !nrow(d)) next
  dc <- names(d)[which(tolower(names(d)) %in% c("date","ym","month","period"))[1]]
  if (is.na(dc)) next
  dv <- suppressWarnings(as.Date(as.character(d[[dc]]))); dv <- dv[!is.na(dv)]
  if (!length(dv)) next
  ## 이진/이산 라벨 컬럼 후보
  bincol <- names(d)[vapply(d, function(x) {
    u <- unique(x[!is.na(x)]); length(u) >= 2 && length(u) <= 5 }, TRUE)]
  bincol <- setdiff(bincol, dc)
  ovl <- length(intersect(unique(mi(dv)), inc$m))
  say("  %-52s %8d %10d %8d %8s", substr(basename(f),1,52), nrow(d), uniqueN(mi(dv)), ovl,
      if (length(bincol)) paste(head(bincol,2), collapse=",") else "없음")
  if (ovl >= 60 && length(bincol)) ok[[length(ok)+1L]] <- list(f=f, cols=bincol, ovl=ovl)
}
say("=== ★착수 판정 ===")
say("  이진 라벨 + PG2 겹침 60개월 이상: **%d건**", length(ok))
say("  %s", if (length(ok) >= 2)
  "★이식 probe 착수 가능 — 라벨 후보를 사전 고정하고 (라벨 x 재료) 전 셀 보고" else
  "★라벨 후보 부족 — mega_spread(FQ-191) 외 비교 대상이 없으면 이식 일반성 검정 불가")
saveRDS(ok, file.path(OUT,"x4_labels.rds"))
say("=== x4 완료 ===")
