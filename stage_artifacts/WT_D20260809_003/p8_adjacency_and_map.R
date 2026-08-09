## WT-D20260809_003 P8 — ①인접 lane 충돌 경고 부기 ②병목 지도 v54
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p8] ", fmt, "\n"), ...)); flush.console() }
suppressPackageStartupMessages(library(jsonlite))
source("02_Infrastructure/ops/frontier_queue_io.R")

## ── ① FQ-170 이 병렬 세션 FQ-167/168 과 같은 재료(Q01) 소비면을 건드린다 — 명시 경고
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-170")
Q$entries[[i]]$adjacency_warning <- paste0(
  "★인접 lane 충돌 주의: 병렬 세션이 등재한 FQ-167(섹터-중립 역전 x 변동성 조건부) · ",
  "FQ-168(섹터-중립 역전 -> 오버레이 리스크 신호, 스코어 하위 25% long 축소)이 **같은 재료(Q01/중립판)의 소비면**을 다룬다. ",
  "본 항목은 '상단절단(D8~D9 선별)' 축이라 설계는 구분되나, 착수 전 FQ-167/168 owner 와 측정 중복(같은 패널·같은 창)을 대조할 것. ",
  "중복 실측은 토큰만이 아니라 **같은 데이터에서 사후선택 자유도**를 늘린다.")
i2 <- which(ids == "FQ-169")
Q$entries[[i2]]$adjacency_warning <- paste0(
  "인접: FQ-108d(vol/tail 8종 z-형태 정보손실 일괄 진단)와 대상 집합이 겹친다. ",
  "FQ-108d 는 z 변환 손실, 본 항목은 평균/순위 괴리 — 축이 다르나 **같은 8종 패널을 돌리므로 한 라운드로 합치는 것이 효율적**. 착수 세션이 판단할 것.")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("FQ-169/170 인접 경고 부기 완료")

## ── ② 병목 지도 v54 (CRLF 보존 바이트 삽입)
p <- "06_Registry/layer_bottleneck_map.md"
raw <- readBin(p, "raw", file.size(p)); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
anchor <- "**\uac31\uc2e0**: 2026-08-09 v53 ("
if (length(gregexpr(anchor, txt, fixed = TRUE)[[1]]) != 1L) { say("\u2605\uc575\ucee4 \ubd88\uc77c\uce58 \u2014 \uc911\ub2e8"); quit(status = 1) }

ins <- paste0(
  "**갱신**: 2026-08-09 v54 (★★★**전이 벽은 단일 현상이 아니다 — 동일 프레임에서 형태가 3종으로 갈린다**[WT-D20260809_003, FQ-166]. ",
  "④construction + **측정무결성** 행 동시 갱신. v53 이 남긴 판별 관문을 실행한 결과다. ",
  "동일-행 프레임(W1×M2 내부조인 **69,282행 · 282개월 2003-01~2026-06 · 630종목 · 월중앙 284**, 유동성 2e8, decile, EW-유니버스 대비 gross): ",
  "**MONOTONE_TOP** = M26_Revenue_Mom(spearman **+0.879**, argmax D10, top **+6.82%/yr**) · M01_PATHQ(+0.770, D10, **+10.47%**) / ",
  "**HUMP** = Q01_EB(+0.188, argmax **D8**, top **−3.41%**) · Q01_neutral(+0.127, argmax D5) / ",
  "**상단-역전형** = D03_EWMA(spearman **−0.685**, argmax D3, top **−5.12%**). ",
  "★**E3 미발화 = 중요한 음성**: Q01 raw 와 중립판이 **둘 다 HUMP** ⇒ v53 이 인용한 WT-003 의 혹은 **중립화 산물이 아니라 Q01 자체 성질**이다. ",
  "중립화 귀속 서술을 쓰지 말 것(귀속 오류 예방). ",
  "★★★**최대 수확 = rank-IC ↔ 평균 프로파일이 갈리는 기전 확립**. D03_EWMA 는 rank-IC **+0.0322(t +3.00, 5재료 중 최강)** 인데 decile **평균** 기울기가 −0.685 다. ",
  "부호 규약 아님을 **먼저** 확인했다(5재료 전부 rank-IC 양수 = 정렬 정상 · W1 원 라운드도 저값 꼬리 배제). ",
  "기전 = rank-IC 는 수익 **순위**를 써서 이상치에 둔감하고 PORT_t·decile 평균은 **원수익**을 써서 꼬리에 지배된다 ⇒ 신호가 수익 **왜도**와 상관되면 구조적으로 갈린다. ",
  "실측: 생 평균 D1(고변동) **+11.84%** vs D10(저변동) +8.25% / 생 **중앙값** D1 **−11.25%** vs D10 **+1.65%** / sd 0.1838 vs 0.0784(**2.34배**) / p99 +0.597 vs +0.223. ",
  "즉 **저변동 이상현상이 중앙값·순위에선 성립하고 평균에선 역전**한다(고변동 우편향이 평균을 들어올림). **top-25 EW 는 평균을 번다** ⇒ rank-IC +3.00 이 PORT_t **−1.73** 으로 뒤집힌다. ",
  "사전등록 예측 **3/3 통과**(중앙값 기울기 +0.503 · (평균−중앙값) 격차 spearman **−0.988** · 왜도 −0.842), 반증 2건 모두 음성, **M26 음성 대조 정상**(sp_mean +0.879 / sp_med +0.794 — 안 갈림). Q01·M01 도 안 갈린다 ⇒ **괴리는 D03 단독 = 변동성 계열 고유**. ",
  "★2026-08-08 인계 큐가 '검증 전'이라 못박은 기전 후보(*rank-IC 가 고변동 꼬리 왜도를 못 봄*)는 **살아 있었다 — 재료를 M26 에 잘못 붙였을 뿐**(M26 기각·D03 지지). ",
  "★★함의: `measurement-graduation` §2 의 rank-IC ADVISORY 강등 근거가 지금까지 **실측 캘리브레이션**뿐이었는데 이제 **기전 설명**이 붙는다. ",
  "⚠**한정(인용 시 필수)**: ①E4(시대 조건부)는 post2015 138개월×10분위라 **검정력과 미분리** — 확정 금지 ②형태 class 가 **해상도 민감**(M01 5분위 UNCLASSIFIED vs 10분위 MONOTONE_TOP) ⇒ **인용 시 해상도·창 병기 의무** ",
  "③형태→소비면 대응은 **가설**(각 형태에서 소비면 성과 미측정 — FQ-170) ④D03 1건으로 vol 계열 일반화 금지(FQ-169) ⑤동일-행 조인이 W1 의 **20.3%** 를 떨어뜨림 — WT-003 원값과 '닮았으나 같지 않다'(재현 아닌 재산출). ",
  "★자가 적대검증 3건 중 하나는 **내 해석이 틀린 것**: 'D10 평균은 소수 극단 음수월 지배' 오답 — 양(+)월 비율 **0.472**, 월 중앙값도 음수 ⇒ 시계열 이상치가 아니라 **순수 횡단면**(정정이 기전을 강화). ",
  "★운영: 후속 FQ 등재가 병렬 세션 선점 ID(FQ-167/168)와 충돌해 조용히 생략됐고 close_round 서술이 일시 거짓이 됐다 → **FQ-169/170 재배정** + 원장 `consume_rule` 에 세션 간 배정 규약 3조 명문화(owner CLAIMED/UNCLAIMED · ID 하드코딩 금지 · frontier_update 는 기록 결과에서 파생). ",
  "상세 = `stage_artifacts/WT_D20260809_003/{alpha_validation.json,challenge_note.md,p1_shape_summary.csv,p3_decile_detail.csv,id_collision_correction.json}`) | ")

txt2 <- sub(anchor, paste0(ins, anchor), txt, fixed = TRUE)
out <- charToRaw(enc2utf8(txt2)); writeBin(out, p)
raw2 <- readBin(p, "raw", file.size(p))
say("지도 기록: %d → %d바이트 · CR %d(원 %d) · LF %d(원 %d) · v54 존재 %s",
    length(raw), length(out), sum(raw2 == as.raw(13)), sum(raw == as.raw(13)),
    sum(raw2 == as.raw(10)), sum(raw == as.raw(10)),
    grepl("2026-08-09 v54", rawToChar(raw2), fixed = TRUE))
say("=== P8 완료 ===")
