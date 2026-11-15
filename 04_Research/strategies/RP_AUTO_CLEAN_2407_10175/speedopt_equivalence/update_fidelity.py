# -*- coding: utf-8 -*-
"""update_fidelity.py — 속도 최적화(LANE-SPEEDOPT-2407-20261115) 뒤 FIDELITY.json 정합 (글자 단위 치환 · 재직렬화 없음)

하는 일(엔진 의미는 손대지 않는다 — 신고서를 새 engine.R 에 맞춘다):
  ① 'engine.R a-b · c' 꼴 줄 참조(paper_steps · windows · self_audit.engine_lines · 맨 줄 참조 2곳)를 새 줄 번호로 옮긴다.
     같은 줄은 difflib 정확 대응 · 옮겨 간 코드(구 .fit_month 머리 · 구 월 루프)는 아래 OVERRIDE 로 새 위치를 직접 준다.
  ② changed 끝에 (24) 실행 계층 항목을 붙인다 · constants 에 실행 계층 상수 2개를 더한다 · self_audit undeclared 메모에 (24)를 더한다.
사용: python update_fidelity.py           (미리 보기 — 쓰지 않는다)
      python update_fidelity.py --write   (FIDELITY.json 을 고쳐 쓴다 · 치환마다 정확히 1회 일치를 단정)
"""
import difflib, io, json, re, sys

D = __file__.replace("\\", "/").rsplit("/speedopt_equivalence/", 1)[0] + "/"
OLD = io.open(D + "engine.pre_speedopt.R", encoding="utf-8").read().split("\n")
NEW = io.open(D + "engine.R", encoding="utf-8").read().split("\n")
for L in (OLD, NEW):
    if L and L[-1] == "":
        L.pop()
NEW_LAST = len(NEW)


def new_line(pattern, start=1):
    """새 engine.R 에서 pattern(정규식)에 맞는 첫 줄 번호(start 이후)"""
    rx = re.compile(pattern)
    for i in range(start - 1, len(NEW)):
        if rx.search(NEW[i]):
            return i + 1
    raise SystemExit("pattern not found in new engine: " + pattern)


EXACT = {}
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(a=OLD, b=NEW, autojunk=False).get_opcodes():
    if tag == "equal":
        for k in range(i2 - i1):
            EXACT[i1 + k + 1] = j1 + k + 1

MI = new_line(r"^\.month_input <- function")          # 1-a 입력 자르기(구 .fit_month 머리의 창 · 멤버 · 벤치 · 수익 절단이 여기로)
FC = new_line(r"^\.fit_core <- function")
FC_NT = new_line(r"^  nT <- inp\$nT", FC)
FC_MEM = new_line(r"^  if \(is\.null\(mem\) \|\| !nrow\(mem\)\) return\(list", FC)
MI_ROWS = new_line(r"^  rows <- i0:i1", MI)
MI_MEM = new_line(r"^  mem <- \.XSL", MI)
MI_INP = new_line(r"^  inp <- list\(d_end", MI)
MI_BR = new_line(r"^  inp\$br <- ", MI)
MI_SUB = new_line(r"^  inp\$sub <- ", MI)
FC_BR = new_line(r"^  br <- inp\$br", FC)
FC_END = new_line(r"^\}$", FC)                        # .fit_core 끝
RUN = new_line(r"^\.run_months <- function")          # 구 월 루프(§2) → 새 §2 실행 계층의 월 실행기 + §3

# 범위 참조(구 문자열 → 새 문자열) — 옮겨 간 코드를 직접 짚는다
OVERRIDE = {
    "386-404 · 418-421": "%d-%d · %d-%d" % (EXACT[386], EXACT[404], MI, FC_NT),
    "406-413 · 422-423": "%d-%d · %d · %d" % (EXACT[406], EXACT[413], MI_MEM, FC_MEM),
    "434-447": "%d · %d-%d" % (MI_SUB, EXACT[434], EXACT[447]),
    "425-432 · 523-533": "%d · %d-%d · %d-%d" % (MI_BR, EXACT[425], EXACT[432], EXACT[523], EXACT[533]),
    "392-404 · 544-557": "%d-%d · %d-%d" % (EXACT[392], EXACT[404], RUN, NEW_LAST),
    "517-541": "%d-%d" % (EXACT[517], FC_END),
    "504-541": "%d-%d" % (EXACT[504], FC_END),
    "396-404 · 420-421": "%d-%d · %d-%d" % (EXACT[396], EXACT[404], MI_ROWS, MI_INP),
    "426-429": "%d · %d-%d" % (MI_BR, FC_BR, EXACT[429]),
    "61-248 · 250-361 · 434-541": "%d-%d · %d-%d · %d-%d" % (EXACT[61], EXACT[248], EXACT[250], EXACT[361], MI, FC_END),
    "37 · 386-404 · 418-421 · 544-557": "%d · %d-%d · %d-%d · %d-%d" % (EXACT[37], EXACT[386], EXACT[404], MI, FC_NT, RUN, NEW_LAST),
    "406-413 · 422-423 · 434-468": "%d-%d · %d-%d · %d · %d-%d" % (EXACT[406], EXACT[413], MI_MEM, MI_SUB, FC_MEM, EXACT[434], EXACT[468]),
    "22-557": "%d-%d" % (EXACT[22], NEW_LAST),
}


def remap(ref):
    if ref in OVERRIDE:
        return OVERRIDE[ref]
    out = []
    for part in re.split(r"\s*·\s*", ref):
        a, _, b = part.partition("-")
        na, nb = EXACT.get(int(a)), (EXACT.get(int(b)) if b else None)
        if na is None or (b and nb is None):
            raise SystemExit("no exact map for %s (in %s) — add an OVERRIDE" % (part, ref))
        out.append("%d-%d" % (na, nb) if b else "%d" % na)
    return " · ".join(out)


raw = io.open(D + "FIDELITY.json", "rb").read().decode("utf-8")
fid = json.loads(raw)
subs = []                                             # (old_substring, new_substring, expected_count)
for m in sorted(set(re.findall(r"engine\.R ((?:\d+(?:-\d+)?)(?:\s*·\s*\d+(?:-\d+)?)*)", raw))):
    subs.append(("engine.R " + m, "engine.R " + remap(m), raw.count("engine.R " + m)))
for x in fid.get("self_audit") or []:
    el = x.get("engine_lines") or ""
    if re.fullmatch(r"\d+(?:-\d+)?(?:\s*·\s*\d+(?:-\d+)?)*", el):
        subs.append(('"engine_lines": "%s"' % el, '"engine_lines": "%s"' % remap(el), raw.count('"engine_lines": "%s"' % el)))
# 맨 줄 참조 2곳(시총 순서 461-465 · SSL 사전분포 모수 171-173)
for bare in ("— 461-465)", "— 171-173"):
    a, b = re.findall(r"\d+", bare)
    subs.append((bare, bare.replace("%s-%s" % (a, b), "%d-%d" % (EXACT[int(a)], EXACT[int(b)])), raw.count(bare)))

ITEM24 = (" (24) 실행 계층(2026-11-15 세션 수정 · 결정 LANE-SPEEDOPT-2407-20261115 · 논문 절차 · 수치 무관 — 구판 = engine.pre_speedopt.R): "
          "① 신호월 병렬 — 달마다 독립(교차월 상태 없음 · 난수 = 2단계의 set.seed(SEED+YYYYMM) 하나)이라 .month_input(주 프로세스가 그 달의 창 · 횡단면만 자른다) → "
          ".fit_core(그 입력만 쓴다)를 PSOCK 작업자(qv_psock_cluster)에서 돌리고 월 순서로 모은다 · 작업자 수 = 환경변수 RP_2407_WORKERS 또는 "
          "min(PAR_MAX_WORKERS, 물리 코어 − PAR_SPARE_CORES) · 작업자는 주 프로세스의 난수 종류 · 정렬 로케일 · data.table 옵션을 그대로 쓴다 · "
          "클러스터를 못 열거나 도중에 끊기면 남은 달을 주 프로세스에서 순차로(같은 결과) · 달마다 '[engine] <신호일> <주석> (초)' 로그 줄을 월 순서로 낸다. "
          "② SSL 추정 캐시 — 변형은 6단계(θ)만 다르므로 1~5단계의 SSL 산출(P · B · steps · draws · r1)과 그 직후 난수 상태를 "
          "<엔진 폴더>/_work/cache/ssl/<sha256>.rds 에 둔다 · 키 = SSL 함수 코드 · 그 함수가 읽는 상수 · R · LAPACK · BLAS 판 · 난수 종류 · "
          "입력 Cm · G · diag(G) · rss0 · T · 시드(입력이 한 비트라도 다르면 다른 키 — 데이터가 바뀌면 자동 무효 · 키에 든 것은 그 신호일까지의 창뿐) · "
          "적중 = 그 계산을 건너뛰고 저장된 난수 상태를 되살린다 · 쓰기 = 임시 파일 → 이름 바꾸기 · 덮기 RP_2407_CACHE_DIR · 끄기 RP_2407_CACHE=0. "
          "③ 좌표하강 갱신의 G[, i] 를 달마다 한 번 만든 열 목록 Gl[[i]] 로 읽는다(같은 값 · 같은 연산 — 허용오차 · 반복 상한 · 알고리즘 불변). "
          "④ 등가 실증 = speedopt_equivalence/README.md(구판 순차 대 새 판 병렬 · 캐시 — 시험 신호월 × 두 변형의 PORTFOLIO 행(Date · Ticker · "
          "Weight 비트 단위 · Leg) · 로그 주석 · 마지막 난수 상태 동일).")
CH_END = "BM_DT(BM_Ret)만 쓴다."
subs.append(('%s"' % CH_END, '%s%s"' % (CH_END, ITEM24), raw.count('%s"' % CH_END)))
C_MINP = ('{"name": "MIN_P", "value": 2, "source": "supplement", "note": "결합(공적분)에 필요한 최소 종목 수 — 미만이면 그 달 산출 없음(구조 가드)"}')
C_NEW = (C_MINP + ',\n    {"name": "PAR_MAX_WORKERS", "value": 6, "source": "supplement", "note": "실행 계층(수치 무관 · changed 24) — 신호월 병렬 작업자 수 기본값의 상한 '
         '(기본 = min(이 값, 물리 코어 − PAR_SPARE_CORES) · 환경변수 RP_2407_WORKERS 가 덮는다)"},\n'
         '    {"name": "PAR_SPARE_CORES", "value": 2, "source": "supplement", "note": "실행 계층(수치 무관 · changed 24) — 작업자 수 기본값에서 남겨 둘 물리 코어 수"}')
subs.append((C_MINP, C_NEW, raw.count(C_MINP)))
UND_END = "상수의 L 접미 제거(constants 값과 글자까지 일치)."
subs.append(('%s"' % UND_END, '%s 2026-11-15 세션 추가: 실행 계층(월 병렬 · SSL 캐시 · 열 목록 — changed 24 · 상수 PAR_MAX_WORKERS · PAR_SPARE_CORES · 수치 불변)."' % UND_END,
             raw.count('%s"' % UND_END)))

bad = [s for s in subs if s[2] != 1 and not s[0].startswith("engine.R ")]
for o, n, c in subs:
    print("[%d] %s\n    -> %s" % (c, o[:110], n[:160]))
if bad:
    raise SystemExit("unexpected match counts: %s" % [b[0][:60] for b in bad])
if "--write" in sys.argv:
    # 한 번에 동시 치환(긴 것 우선 대안) — 새로 넣은 참조가 다른 구 참조에 다시 걸리는 연쇄 치환이 없다
    table = {o: n for o, n, c in subs}
    rx = re.compile("|".join(re.escape(o) for o in sorted(table, key=len, reverse=True)))
    hits = {}
    def _rep(m):
        hits[m.group(0)] = hits.get(m.group(0), 0) + 1
        return table[m.group(0)]
    out = rx.sub(_rep, raw)
    miss = [o[:80] for o, n, c in subs if hits.get(o, 0) != c]
    if miss:
        raise SystemExit("replacement counts differ from preview: %s" % miss)
    json.loads(out)                                                  # 문법 단정
    io.open(D + "FIDELITY.json", "wb").write(out.encode("utf-8"))
    print("written:", D + "FIDELITY.json", "· substitutions", sum(hits.values()))
