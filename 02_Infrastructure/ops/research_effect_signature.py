# ★RETIRED (v10 2026-08-29 · 헤더 2026-09-03) — 무인 리서치 레인 퇴역: morning_run 에서 철거됐고
#   예약작업·bat 호출 0. 파일은 사료(08_Tests 가 경로로 직접 실행하므로 이동·삭제 금지).
#   재개 레시피 = git 태그 pre-v10-2layer 의 morning_run.sh [0.55]~[0.6] 구간.
# -*- coding: utf-8 -*-
"""research_effect_signature.py — 무인 런의 **효과**를 원장에서 직접 읽는다 (2026-08-22 신설).

왜 있나 (실사고 2026-08-22 16:31):
  qepm_dossier 첫 런이 WT-D20260822_004 를 SPEC_APPROVED → ALPHA_DONE 으로 전이시키고
  alpha_package.json · alpha_validation.json · artifact_lineage.json 을 만들었다.
  **일은 다 했는데** stdout 에 `MODEQ_DONE` 을 안 냈고, 그래서 러너의 zero_progress 가드가
  "아무것도 처리되지 않음" 으로 경보했다 — 실질 오경보다.

★기전: 그 가드는 **에이전트의 자기보고**(stdout 한 줄)만 봤다. 오늘 하루 내내 확인된 교훈은
  그 반대다 — **원장이 진실이고 자기보고는 보조다**. 자기보고가 빠지는 건 흔하고(프롬프트를
  지켜도 형식을 놓친다), 그때마다 오경보가 나면 경보가 '학습된 무시'가 된다.

⇒ 이 모듈은 런 전후로 원장 상태를 지문화해 **효과가 있었는지**를 독립적으로 판정한다.
  판정 조합:
    · 마커 있음            → 진척 (자기보고 + 효과 무관하게 신뢰)
    · 마커 없음 ∧ 지문 변화 → 진척 (자기보고 누락 — 경보 아님, 로그로만 남긴다)
    · 마커 없음 ∧ 지문 동일 → **진짜 무진척** → zero_progress 경보

사용:
  python research_effect_signature.py <root>            # 지문 1줄 출력
  python research_effect_signature.py <root> --compare <before>   # 같으면 SAME, 다르면 CHANGED
  python research_effect_signature.py <root> --scope WT-A,WT-B [--compare <before>]
      # scope 를 주면 그 WT 들만 본다 = "내가 겨눈 것이 움직였나"(귀속용).
      # 전역과 scoped 는 **다른 물음**이므로 둘 다 재고 용도를 나눠 쓴다.
"""
import hashlib
import io
import json
import glob
import os
import sys


def _n(path, key="modules"):
    """원장 항목 수 — 부재/손상은 -1(구분 가능한 값). 0 과 섞지 않는다."""
    try:
        with io.open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except Exception:
        return -1
    v = d.get(key)
    if v is None:
        return -1
    return len(v)


def signature(root, scope=None):
    """런의 효과가 닿는 표면만 모아 지문을 만든다.

    ★파일 mtime 은 쓰지 않는다 — 병렬 세션이나 무관한 재작성으로도 바뀌어
      '변화' 를 과잉 탐지한다. **내용에서 파생된 수치**만 쓴다.

    scope: WT id 목록(list). 주면 그 WT 들만 본다 = "내가 겨눈 것이 움직였나".
      안 주면 전역 = "무언가 움직였나". 두 물음은 다르고, 답도 달라야 한다
      (2026-08-22 오귀속 사고 — 전역 지문으로 남의 세션 진척을 내 성과로 읽었다).
      ★scope 를 주면 원장 축(catalog/quarantine/method)은 **빼지 않는다** — 그 축은
      WT 로 귀속되지 않지만 이 런의 정당한 산출일 수 있고, 빼면 반대로 놓친다.
    """
    parts = []
    parts.append("catalog=%d" % _n(os.path.join(root, "06_Registry", "module_catalog.json")))
    parts.append("quarantine=%d" % _n(os.path.join(root, "06_Registry", "module_quarantine.json")))
    parts.append("methods=%d" % _n(os.path.join(root, "06_Registry", "method_registry.json"),
                                   "methods"))
    # method_registry 의 측정 기입 수 — 등재 없이 측정만 채우는 레인이 있다
    try:
        with io.open(os.path.join(root, "06_Registry", "method_registry.json"),
                     encoding="utf-8") as fh:
            ms = json.load(fh).get("methods") or []
        parts.append("measured=%d" % sum(
            1 for m in ms if str((m or {}).get("measurement_status") or "").strip()))
    except Exception:
        parts.append("measured=-1")

    # WT 의 phase 집합 + 산출물 개수 — dossier/promotion 레인의 효과가 여기 있다
    wt = []
    _want = set(scope or [])
    for d in sorted(glob.glob(os.path.join(root, "qepm", "mailbox", "worktask", "WT-*"))):
        if _want and os.path.basename(d) not in _want:
            continue
        try:
            with io.open(os.path.join(d, "status.json"), encoding="utf-8") as fh:
                st = json.load(fh)
            ph = str(st.get("current_phase") or st.get("phase") or "")
        except Exception:
            ph = "?"
        try:
            nf = len(os.listdir(d))
        except Exception:
            nf = -1
        wt.append("%s:%s:%d" % (os.path.basename(d), ph, nf))
    parts.append("wt=%d" % len(wt))
    parts.append("wthash=%s" % hashlib.sha256("|".join(wt).encode("utf-8")).hexdigest()[:16])
    return ";".join(parts)


def main(argv):
    if not argv:
        sys.stderr.write("usage: research_effect_signature.py <root> [--compare <sig>]\n")
        return 2
    root = argv[0]
    scope = None
    if "--scope" in argv:
        raw = argv[argv.index("--scope") + 1]
        scope = [x for x in raw.replace(" ", "").split(",") if x and x != "?"]
        if not scope:          # "?" 뿐이면 범위 미상 — 전역으로 되돌린다(조용히 빈 범위 금지)
            scope = None
    sig = signature(root, scope)
    if "--compare" in argv:
        before = argv[argv.index("--compare") + 1]
        print("SAME" if before == sig else "CHANGED")
        return 0
    print(sig)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
