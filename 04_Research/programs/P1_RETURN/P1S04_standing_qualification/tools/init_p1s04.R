#!/usr/bin/env Rscript
## P1S04(P1 상설 자격 · 레인 갈래 판 3 · round_core v4) 사양 만들기 — 등록 전에 한 번 돈다(사양이 이미 있으면 멈춘다).
##   근거: 도훈 결정 P1S02-EDITION3-REGISTER-LATER-20261114 — '판 3 등록(같은 시드 · 코어 v4 · v3.5 핀) · 측정 = P1R04 · P1S03 측정 뒤 첫 GPU 창'.
##   판 2(P1S02 · 코어 v3)는 등록(11-12) 뒤 등급 v3.5 계약 교체(11-14 16:03 · 317a9c0e0)로 핀 6 이 갈려 측정 전(판정 0건)에 멈췄다 —
##   상설 판에는 재핀 경로가 없다(v3 standing.R:231 · 판단 J-20261114-002). 그래서 같은 규칙을 새 판으로 다시 등록한다.
##   승계(무수정): 규칙 · 문턱(P1 템플릿 — 코어가 정본에서 읽는다) · 시드 2(E2 · E3 — 같은 생성 함수 · 같은 원본 사양) · 입구(레인 · audit_admit ·
##     orientation_admit · 판 2 의 사유 셋 — 코어 v4 레인 기본값과 판 2 scan 이 같다) · 판 2 의 노출 9 줄 · 결론 범위 18 줄(판 2 사양에서 그대로 읽는다) · pins.files 13.
##   바뀐 것: 코어 v3 → v4(입구 갈래 track = lane · 판 번호 3 · 결론 범위 앞에 코어 v4 레인 철학 줄 2 자동 · 통과 보고 단위 push_each(기본)) ·
##     등급 v3.5 계약이 코어 기본 핀으로 묶인다 · 시드 칸 코드 P1S04_* · 시험 목록 = 없음(도훈 11-12 '테스트 좀 그만하자' · P1S03 선례 — 코어 v4 출시 시험 46/46 이 판정 경로를 덮는다).
##   실행: Rscript 04_Research/programs/P1_RETURN/P1S04_standing_qualification/tools/init_p1s04.R   (작업 디렉터리 = 저장소 루트)
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
stopifnot(identical(RC_VERSION, "v4"))
root <- rc_root()
rd <- "04_Research/programs/P1_RETURN/P1S04_standing_qualification"
P2 <- rc_json_read(file.path(root, "04_Research/programs/P1_RETURN/P1S02_standing_qualification/round_spec.json"))
if (!identical(P2[["round_id"]], "P1S02_standing_qualification")) stop("판 2 사양 판독 실패")
fam <- "2002.06975"
paper <- list(url = "https://arxiv.org/abs/2002.06975",
              title = "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management", paper_key = fam)
nf <- as.integer(rc_standing_nf_prior(fam, root))        # 계보 앞선 사전등록 · 상설 원장 회계 최댓값 — 시드 = 무가산(그대로)
basis <- sprintf("P1S04 시드(같은 판본 기준 재측정 — 시행 수 무가산 · P2R04 RX0 · P1S02 선례): 계보 %s 앞선 사전등록 · 상설 원장 회계 최댓값 %d 그대로", fam, nf)
dir.create(file.path(root, rd, "specs"), recursive = TRUE, showWarnings = FALSE)
f2 <- file.path(rd, "specs/P1S04_E2_C0.json"); f3 <- file.path(rd, "specs/P1S04_E3_RX0.json")
if (file.exists(file.path(root, f2)) || file.exists(file.path(root, f3))) stop("시드 칸 사양이 이미 있다 — 덮어쓰지 않는다")
rc_json_write(rc_p1_cell_spec("P1S04_E2_C0", "04_Research/strategies/RP_AUTO_2002_06975/engine.R", paper, fam, nf, basis, root = root), file.path(root, f2))
rc_json_write(rc_standing_seed_respec("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E3_C0.json", "P1S04_E3_RX0", nf, basis, root), file.path(root, f3))
seeds <- list(list(code = "P1S04_E2_C0", engine = "E2", role = "reference", spec = f2),
              list(code = "P1S04_E3_RX0", engine = "E3", role = "reference", spec = f3))

purpose <- paste0(
  "P1 엔진 자격 규칙을 레인 갈래 판 3 으로 다시 등록한다(도훈 결정 P1S02-EDITION3-REGISTER-LATER-20261114). ",
  "판 2(P1S02 · 코어 v3)는 등록 뒤 등급 v3.5 계약 교체로 핀이 갈려 측정 전(판정 0건)에 멈췄다 — 상설 판에는 재핀 경로가 없다. ",
  "판 3 은 판 2 의 규칙 · 문턱 · 시드 · 입구 사유 · 결론 범위를 그대로 쓰고, 코어를 v4(입구 갈래 · 기저 풀 관문 · 결합용 뷰 지문)로 옮기며 등급 v3.5 계약을 핀으로 묶는다. ",
  "아래는 판 2 의 목적 문장 그대로다 — ", P2[["purpose"]])
hypothesis <- paste0("판 2 와 같다 — ", P2[["hypothesis"]])
exposures <- c(as.list(unlist(P2[["exposures"]])), list(
  "(판 3) 위 9 줄은 판 2 의 노출 고지 그대로다(판 2 는 측정 0건 · 판정 0건으로 멈췄다 — 판 2 의 시드 결과는 없다). 판 3 시드 결과는 등록 시점에 없다.",
  paste0("(판 3) Q 는 11-13~15 자체 사양 갈래(P1R03 · P1R04 · P1S03)의 IS 판정과, 이음매 세션 통지(11-14)로 P1R03 엔진의 사람 쪽 지표(시험 창 · 전 기간)를 본 상태다 — ",
         "이 판의 입구(레인 엔진)와 시드 계보(2002.06975)와 겹치지 않고, 규칙 · 문턱 · 입구는 판 2 그대로라 판정에 닿지 않는다(수치는 여기 옮기지 않는다)."),
  "(판 3) 코어 v4 의 레인 입구 기본값은 판 2 scan 과 같다(orientation_admit 만 판 2 값 engine_native · factor_db_static 로 덮어쓴다) — 입구 규칙을 결과를 보고 바꾸지 않았다(레인 미리보기는 아직 보지 않았다)."))
conclusion_scope <- c(as.list(unlist(P2[["conclusion_scope"]])), list(
  paste0("(판 3) 위 줄들은 판 2 결론 범위 그대로다 — '판 2' 라고 적힌 정책(입구 사유 셋 · 측정 관문 · 달 스냅 · 시드 서술)은 판 3 에도 같다. ",
         "판 3 은 판 2(판정 0건 · 보류 고정)의 항목을 이어받지 않는다(rejudge_prior_editions = false) — 판 3 등록 뒤 판 2 는 새 항목을 받지 않는다(같은 갈래의 더 높은 판 · v3 코드는 판 번호만 본다)."),
  "(판 3) 시드 측정은 GPU 창에서 한다(도훈 결정 — 레인 양보 · 워커 3 · PYTHON_CPU_COUNT=4) · 감시 셸은 판 2 의 것을 판 3 경로로 옮겨 쓴다 · 판 3 첫 판정 전 점검 = 판 2 DESIGN §5 절차 그대로."))

sp_path <- rc_init_standing_p1(file.path(root, rd), "P1S04_standing_qualification", seeds, purpose, hypothesis, edition = 3L,
                               scan = list(orientation_admit = list("engine_native", "factor_db_static")),
                               exposures = exposures, conclusion_scope = conclusion_scope, tests = list(), root = root)
sp <- rc_json_read(sp_path)
p2files <- vapply(P2[["pins"]][["files"]], function(x) if (is.list(x)) x[["path"]] else x, "")
sp[["pins"]] <- list(files = as.list(p2files),
  basis = paste0("판 2(P1S02) pins.files 13 그대로 — ", P2[["pins"]][["basis"]], " (판 3: 코어 v4 기본 핀이 등급 v3.5 계약 · 코어 파일을 따로 묶는다)"))
rc_standing_validate(sp, root)
rc_json_write(sp, sp_path)
cat(sprintf("[init_p1s04] 사양 %s · 판 %s · 갈래 %s · 시드 n_family %d · 노출 %d · 결론 범위 %d · 생성 함수 핀 %s\n", rc_rel(sp_path, root),
            sp[["standing_cfg"]][["edition"]], sp[["standing_cfg"]][["track"]], nf, length(sp[["exposures"]]), length(sp[["conclusion_scope"]]),
            sp[["standing_cfg"]][["generator_pin"]][["fn_md5"]]))
