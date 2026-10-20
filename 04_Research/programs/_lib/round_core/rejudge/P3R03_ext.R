## P3R03 고유 규칙(round_ext) — 코어 P3 템플릿 위에서 P3R03(원문 고도화 구성 5종) 판정을 재현한다(재판정 · 픽스처 대조).
##   이 라운드가 코어에 더하는 것 = 방법 표(카탈로그 id · 진단 줄 태그)와 파일 이름뿐이다. 판정 단계 · 라운드 판정 = round_core v1(pair.R · p3.R).
##   출처: P3R03 evaluate.R L15-18(등록 c7166d2ca 판 그대로).
P3R03_ROUND_ID <- "P3R03_advanced_construction"
P3R03_METHODS <- list(HRP = list(catalog = "paper:HRPLdP2016", tag = "hrp"), NCO = list(catalog = "paper:NCOLdP2019", tag = "nco"),
                      MRE = list(catalog = "paper:MichaudResampledMinVar", tag = "michaud"), CVR = list(catalog = "paper:CVaRLPRU2000", tag = "cvar"),
                      ERC = list(catalog = "paper:ERCMRT2010", tag = "erc"))
P3R03_T <- rc_p3_template(cfg = list(methods = P3R03_METHODS))
p3r03_R <- function(root, res, out, perf_env = NULL, ...) {
  rd <- file.path(root, "04_Research/programs/P3_CONSTRUCTION", P3R03_ROUND_ID)
  pp <- file.path(root, "stage_artifacts/programs/P3_CONSTRUCTION", P3R03_ROUND_ID, "prereg.json")
  utils::modifyList(list(round_id = P3R03_ROUND_ID, program = "P3_CONSTRUCTION", tag = "P3R03", pre = fromJSON(pp, simplifyVector = FALSE), prereg_path = pp,
                         root = root, res = res, out = out, precheck = file.path(res, "precheck.json"),
                         fingerprint = list(script = file.path(rd, "fingerprint.sh"), args = character(0), record_args = character(0)),
                         evaluate_md5 = rc_md5(file.path(rd, "evaluate.R")), schema = "p3r03_evaluation_v2", out_file = "evaluation.json",
                         check_pins = FALSE, cell_eval = function(cell) rc_eval_cell_single_legacy(res, cell), perf_env = perf_env), list(...))
}
## 핀 재대조(P3R03 판 — 종류 검사 없음 · 카탈로그 문구) — 출처: P3R03 L250-272
p3r03_pin_mismatches <- function(pre, root) rc_legacy_pin_mismatches(pre, root, kinds = NULL, catalog_label = "카탈로그 엔트리")
