## WT-D20260809_001 P8 — FQ-166 정련: 병렬 세션 WT-D20260808_003 의 Q01 '혹' 실측을 반영
## (독립 라운드가 이미 데이터 1점을 제공 — 질문이 '벽이 단일인가'에서 '무엇이 형태를 가르는가'로 좁혀진다)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p8] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
say("원장 read: 항목 %d (병렬 세션 등재분 보존 확인 목적)", length(Q$entries))

i <- which(ids == "FQ-166")
if (!length(i)) { say("★FQ-166 부재 — 중단"); quit(status = 1) }

Q$entries[[i]]$title <- "전이 벽 형태 분류 — 무엇이 '단조(상단 정보 有)' 와 '혹(상단 정보 無)' 를 가르는가"
Q$entries[[i]]$hypothesis <- paste0(
  "2026-08-09 하루에 독립 두 라운드가 **정반대 분위 형태**를 실측했다. ",
  "M26_Revenue_Mom(WT-D20260809_001): decile 단조성 spearman +0.879 · D10 연초과 +6.550%(t 2.822) ⇒ 상단에 정보 有, ",
  "갭은 비용(+0.497 t)+벤치(+0.777 t) 로 가법 분해. ",
  "중립 Q01_EB(WT-D20260808_003): EW 대비 5분위 [−3.81 +1.37 +3.05 +1.78 −2.41] = **혹** ⇒ 상단에 정보 無, 최상위가 EW 에도 뒤짐. ",
  "∴ '전이 벽'은 단일 현상이 아니다. 남은 질문은 **무엇이 형태를 가르는가** — ",
  "재료 종류(컨센서스 개정 vs 이익 서프라이즈)인가, 중립화 처리인가, 시대(전표본 vs post-2015)인가, 분위 해상도인가.")
Q$entries[[i]]$ev_rationale <- paste0(
  "형태가 소비면을 직접 가른다: 단조형은 composite/비용축, 혹형은 중간분위/상단절단. ",
  "형태를 먼저 재면 소비면 선택이 추측이 아니라 도출이 된다. ",
  "★독립 데이터 2점이 이미 있고 세 재료(D03_EWMA PORT_t −1.73 포함)의 패널이 전부 존재해 저비용.")
Q$entries[[i]]$wall_check <- paste0(
  "진단 라운드 — 자본 주장 없음. ★**동일 프레임 필수**: 두 관측은 5분위/post-2015/중립 vs 10분위/전표본/원신호로 ",
  "프레임이 다르다. 수치를 같은 자로 읽지 말고 **한 프레임에서 재산출**한 뒤에만 형태를 대비한다. ",
  "사다리(net→gross 0bps→EW-basis)의 반사실 단은 counterfactual_diag 라벨 의무.")
Q$entries[[i]]$next_action <- paste0(
  "①M26 · Q01_EB · D03_EWMA 를 **동일 프레임**(동일 분위수·동일 창·원신호/중립 양판)으로 분위 프로파일 재산출 ",
  "②각 재료에 net→gross→EW-basis 사다리 적용해 갭 성분 크기 대조 ",
  "③형태 갈림의 후보 설명변수(재료군·중립화·시대) 중 어느 것이 형태와 정렬되는지 ",
  "④음수 PORT_t(D03 −1.73)가 사다리 어느 단에서도 회복 안 되면 '제3 형태' 확립 ",
  "⑤형태별 소비면 라우팅 규약 초안 → 이후 라운드의 첫 진단으로 제도화")
Q$entries[[i]]$source_refs <- list(
  "stage_artifacts/WT_D20260809_001/alpha_validation.json (M26 단조형)",
  "memory: project-m26-transition-gap-additive-decomposition-20260809",
  "memory: project-transfer-wall-is-no-top-information-20260809 (Q01 혹형)")
Q$updated <- "2026-08-09"
say("FQ-166 정련 완료")

write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("재읽기: 항목 %d · FQ-166 status=%s", length(Q2$entries),
    Q2$entries[[which(vapply(Q2$entries, function(e) as.character(e$id)[1], character(1)) == "FQ-166")]]$status)
