#!/usr/bin/env Rscript
## P1S04 사양 초안 v2 — 격리 변경분 점검 v1(prereg_draft_review_v1.md · ok · 필수 0 · 권고 3 · 선택 8)의 사양 문장 항목만 반영한다(규칙 · 문턱 · 시드 · 입구 · 핀 불변).
##   사양 안: R-1 (가) 결론 범위 줄 1(레인 갈래 통과 칸의 철학 판독 = 절차) · R-2 (가) + S-4 정정 줄 1 · S-1 노출 [10] 문구 · S-2 결론 범위 [21] · [22] 문구.
##   사양 밖(DESIGN): R-3 · S-3 · S-5 · S-6 · S-7 · S-8.
##   판 2 에서 옮긴 줄([3]~[20])은 고치지 않는다(판 2 와 같은 문장 — 정정은 뒤에 붙인 줄이 맡는다).
##   실행: Rscript 04_Research/programs/P1_RETURN/P1S04_standing_qualification/tools/init_p1s04_v2.R  → 그다음 round.sh <판> draft(v2) → 변경분 점검
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
stopifnot(identical(RC_VERSION, "v4"))
root <- rc_root()
rd <- "04_Research/programs/P1_RETURN/P1S04_standing_qualification"
spf <- file.path(root, rd, "round_spec.json")
if (file.exists(file.path(root, rd, "prereg.json"))) stop("[init_p1s04_v2] 이미 등록됐다 — 사양을 고치지 않는다")
D <- rc_json_read(file.path(root, rd, "drafts.json"))[["versions"]]
if (length(D) != 1L || !identical(D[[1]][["review"]][["verdict"]], "ok")) stop("[init_p1s04_v2] drafts.json = 초안 v1 · 점검 ok 하나여야 한다")
sp <- rc_json_read(spf)
E <- sp[["exposures"]]; C <- sp[["conclusion_scope"]]
if (length(E) != 12L || length(C) != 22L || !startsWith(E[[10]], "(판 3) 위 9 줄은") || !startsWith(C[[21]], "(판 3) 위 줄들은") || !startsWith(C[[22]], "(판 3) 시드 측정은"))
  stop("[init_p1s04_v2] 사양 줄 위치가 초안 v1 과 다르다")
## S-1
E[[10]] <- paste0("(판 3) 위 9 줄은 판 2 의 노출 고지 그대로다. 판 2 원장은 측정 성공 0건 · 판정 0건이다(E2 측정 시도 1회 실패 · 산출 없음 · 성과 값 없음 — Q 는 그 시도의 로그를 보지 않았다). ",
                  "판 3 시드 결과는 등록 시점에 없다.")
## S-2
C[[21]] <- paste0("(판 3) 위 [3]~[20] 18 줄은 판 2 결론 범위 그대로다(앞 [1] · [2] = 코어 v4 레인 철학 줄) — '판 2' 라고 적힌 정책(입구 사유 셋 · 측정 관문 · 달 스냅 · 시드 서술)은 판 3 에도 같다. ",
                  "판 3 은 판 2(판정 0건 · 보류 고정)의 항목을 이어받지 않는다(rejudge_prior_editions = false) — 판 3 등록 뒤 판 2 는 새 항목을 받지 않는다(같은 갈래의 더 높은 판 · v3 코드는 판 번호만 본다).")
C[[22]] <- paste0("(판 3) 시드 측정은 GPU 창에서 한다(도훈 결정 — 레인 양보 · 워커 3 · PYTHON_CPU_COUNT=4) · 감시 셸 · 판정 전 점검은 판 2 의 것을 코어 v4 로 옮겨(지문 = v4 · 결합용 뷰 포함 · v4 코어 적재) 판 3 경로로 쓴다 · ",
                  "판 3 첫 판정 절차 = 판 3 DESIGN §5(판 2 §5 승계 · 리허설 없음).")
## R-1 (가)
C[[23]] <- paste0("(판 3) 코어 v4 기저 풀의 철학 관문(philosophy_unread · philosophy_hold)과 사슬 판 등록의 기저 판독 확인은 자체 사양 통과 칸에만 걸린다 — 이 판(레인 갈래) 통과 칸 · 시드에는 기계 관문이 없다. ",
                  "[20] 의 '사슬 판 등록은 그 판독 없이 기저를 받지 않는다'는 이 판에서 절차로 지킨다: 이 판 통과 칸을 기저 · 블렌드 상대로 받는 사슬 판 등록 · 걸음 전에 그 칸의 철학 P2 리뷰 id(superfan-mark --kind pass --p2)를 사슬 판 판단 T1 이 확인한다 · 기계 관문은 다음 코어 판 후보.")
## R-2 (가) + S-4
C[[24]] <- paste0("(판 3 정정) 위 판 2 줄에서 '코어 v3' 라고 적힌 동작(측정 관문 · 최신 판 판독 · 기저 풀 레인 행 · 실효 시작 한계)은 v4 레인 갈래에서 같다. ",
                  "[20] 의 괄호 '판정 줄에 귀속 없는 위기 하락노출이 실린다 — 다음 코어 판에서 가른다'는 v4 에서 갈렸다(판정 줄 · 보고 열 · 시험 창 줄) — 다만 통과 엔진의 철학 P2 한 줄을 일 요약에 싣는 자동 통로는 v4 에도 없어 판 2 DESIGN §5 의 절차(세션이 싣는다)를 따른다. ",
                  "[13] 의 '같은 학습창 · 입력 · 시드'는 '같은 학습창 · 시드(자료 판은 다를 수 있다 — DNN 캐시는 입력 내용 주소)'로 읽는다(판 2 점검 v2 S-6).")
sp[["exposures"]] <- E; sp[["conclusion_scope"]] <- C
sp[["changes_after_review"]] <- list(
  paste0("격리 변경분 점검 v1(prereg_draft_review_v1.md · ok · 필수 0 · 권고 3 · 선택 8) → 초안 v2: R-1 (가) 결론 범위 [23](레인 갈래 통과 칸의 철학 판독 = 절차 · 사슬 판단 T1 이 확인) · ",
         "R-2 (가) + S-4 결론 범위 [24](옮긴 줄의 '코어 v3' · [20] 괄호 · [13] '입력' 정정) · S-1 노출 [10](판 2 측정 시도 1회 실패) · S-2 결론 범위 [21] · [22] 문구. 규칙 · 문턱 · 시드 · 입구 · 핀 불변."),
  "사양 밖(DESIGN): R-3 감시 셸 · 판정 전 점검 v4 이식 · 측정 시간 가정 다시(등록 뒤 · 측정 전) · S-3 시험 수 71/0 · 레인 scan 순서(dry-run → --max 0 → scan) · S-5 상설 단계만 · S-6 torch 판 확인 · S-7 핀 창 · S-8 scan_stale.")
rc_standing_validate(sp, root)
rc_json_write(sp, spf)
cat(sprintf("[init_p1s04_v2] 사양 %s · md5 %s · 노출 %d · 결론 범위 %d\n", rc_rel(spf, root), rc_md5(spf), length(sp[["exposures"]]), length(sp[["conclusion_scope"]])))
