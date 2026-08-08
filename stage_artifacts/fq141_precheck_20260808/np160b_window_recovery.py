"""NP-160b — 큐가 가리키는 산출물에서 '측정 창'을 역추출할 수 있는 비율.

NP-157c 의 창-핸디캡 지도를 기존 기각에 결합하려면 각 FQ 의 측정 창(개월수/종료월)이 필요하다.
큐 본문에는 1.3% 밖에 없다(FQ-160 실측). 아티팩트에는 있을 수 있고, 그 회수율이 소비의 실제 관문이다.

★초판 결함 수리 (2026-08-08, 자체 적발):
  초판은 source_refs 원소를 **무조건 경로로 간주**하고 os.path.exists 를 걸었다. 그런데 그 필드는
  "memory: project-...", "trigger: 도훈 2026-07-13 ...", "parent: FQ-037 ..." 같은 **비-경로 참조**가 다수다.
  또 산문에서 디렉터리 없는 basename(alpha_validation.json 등)을 뜯어내 존재 검사를 걸었다.
  결과: '끊긴 참조 34.8%' 라는 **그럴듯한 오답**. = 경로로 *식별되지 않은* 문자열에 *존재* 검사를 건 것
  (이 저장소가 반복 검거해온 계통을 감사 도구가 그대로 재현).
  수리: ①비-경로 접두사 제거 ②디렉터리 구분자(/)를 포함한 토큰만 경로 후보 ③basename-only 는
  별도 카테고리로 분리 계상(존재 검사 대상 아님) ④'경로 없음'과 '경로 있으나 미해결'을 구분.

read-only.
"""
import json, io, os, re
from collections import Counter

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
os.chdir(ROOT)

Q = json.load(io.open("06_Registry/alpha_frontier_queue.json", encoding="utf-8"))
E = Q["entries"]

NONPATH_PREFIX = re.compile(r'^\s*(memory|trigger|parent|literature|note|ref|source|paper|dohoon|inherits)\s*:',
                            re.I)
# 경로 후보 = 디렉터리 구분자를 포함하고 알려진 확장자로 끝나거나 디렉터리처럼 보이는 토큰
PATH_TOKEN = re.compile(r'(?:[0-9A-Za-z_.\-]+/)+[0-9A-Za-z_.\-]+')
BASENAME_ONLY = re.compile(r'^[0-9A-Za-z_.\-]+\.(?:json|md|csv|parquet|rds|R)$')

PATH_FIELDS = ["source_refs", "result_ref", "result_artifacts", "artifacts",
               "verdict_artifact", "outputs", "result_lcode", "l_code"]


def harvest(e):
    """반환: (해결가능 경로 set, basename-only set, 비경로 참조 수)"""
    paths, basenames, nonpath = set(), set(), 0
    raw = []
    for f in PATH_FIELDS:
        v = e.get(f)
        if v is None:
            continue
        raw.extend(v if isinstance(v, list) else [v])
    # 임시 필드 109종을 필드명으로 열거할 수 없으므로 본문 전체에서도 경로 토큰을 수확
    raw.append(json.dumps(e, ensure_ascii=False))

    for item in raw:
        if not isinstance(item, str):
            continue
        if NONPATH_PREFIX.match(item):
            nonpath += 1
            # 접두사 뒤에도 경로가 섞일 수 있으므로 계속 스캔
        for tok in PATH_TOKEN.findall(item):
            tok = tok.strip(".,)]}\"'")
            if tok:
                paths.add(tok)
        for w in re.split(r'[\s,+;]+', item):
            w = w.strip(".,)]}\"'")
            if BASENAME_ONLY.match(w):
                basenames.add(w)
    return paths, basenames, nonpath


PAT_NMONTH = re.compile(r'"?n_months"?\s*[:=]\s*(\d{2,4})|(\d{2,4})\s*개월|\b(\d{2,4})\s*months\b')
PAT_RANGE = re.compile(r'(20\d{2})[-./](\d{1,2})\D{0,4}[~\-–]\D{0,4}(20\d{2})[-./](\d{1,2})')

stat = Counter()
per_entry = []
for e in E:
    paths, basenames, nonpath = harvest(e)
    exists = sorted(p for p in paths if os.path.exists(p))
    stat["entries"] += 1
    if paths:
        stat["entries_with_path_token"] += 1
    if exists:
        stat["entries_with_resolvable_path"] += 1
    if paths and not exists:
        stat["entries_path_token_but_unresolved"] += 1
    if not paths and basenames:
        stat["entries_basename_only"] += 1
    if not paths and not basenames:
        stat["entries_no_path_at_all"] += 1

    found = None
    probed = 0
    for p in exists:
        if os.path.isdir(p):
            continue
        try:
            if os.path.getsize(p) > 8_000_000:
                continue
        except OSError:
            continue
        if not p.lower().endswith((".json", ".md", ".csv")):
            continue
        probed += 1
        if probed > 8:
            break
        try:
            t = io.open(p, encoding="utf-8", errors="replace").read(400_000)
        except Exception:
            continue
        if PAT_NMONTH.search(t) or PAT_RANGE.search(t):
            found = p
            break
    if found:
        stat["entries_window_recoverable"] += 1
    per_entry.append({"id": e["id"], "n_path_tokens": len(paths), "n_resolvable": len(exists),
                      "n_basename_only": len(basenames), "n_nonpath_refs": nonpath,
                      "window_recoverable": bool(found), "window_src": found})

n = stat["entries"]
print(f"=== NP-160b (수리본) 창 역추출 회수율 · n={n} ===")
for k in ["entries_with_path_token", "entries_with_resolvable_path",
          "entries_path_token_but_unresolved", "entries_basename_only",
          "entries_no_path_at_all", "entries_window_recoverable"]:
    v = stat[k]
    print(f"  {k:<38} {v:>4}  ({v/n*100:>5.1f}%)")

rec = [r for r in per_entry if r["window_recoverable"]]
print(f"\n★창 회수 가능 = {len(rec)}/{n} ({len(rec)/n*100:.1f}%) — 이 값이 NP-157c 소비 커버리지의 하한")
print("  예:", [r["id"] for r in rec[:10]])
unres = [r for r in per_entry if r["n_path_tokens"] and not r["n_resolvable"]]
print(f"\n★경로 토큰 있으나 미해결 = {len(unres)} — 상대경로/이전 위치/오타 혼재 가능. 개별 확인 없이 '끊김' 단정 금지")
print("  예:", [r["id"] for r in unres[:10]])

json.dump(per_entry, io.open("stage_artifacts/fq141_precheck_20260808/np160b_per_entry.json",
                             "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("\n저장: np160b_per_entry.json")
