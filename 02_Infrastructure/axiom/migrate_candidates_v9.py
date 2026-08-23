#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""migrate_candidates_v9.py — v9 "Lean Loop" 일회성 이관 (2026-08-23, 계획서 §3.4(b)).

무엇을 왜 옮기는가
------------------
구 규약은 식별자에 **날짜**를 넣었다.
  candidates : `CAND_<YYYYMMDD>_<mode>_<family>_<polarity>_<L-code 3개>.json`
  review_log : `AX-PENDING_<candidate_id>_<YYYYMMDD>[_<HHMMSS>].json`
그 결과 ① 내용이 하나도 안 바뀌어도 매주 새 파일이 생겼고(169 삭제→86 신규)
② 같은 클러스터가 최대 24회 동일 점수로 재채점됐으며 ③ candidate_id 가 길어
review_log 쓰기가 MAX_PATH 를 넘겨 **무음 crash** 한 사례가 있다.

v9 는 식별자를 **클러스터의 정체(=멤버 L-code 집합의 sha1 12-hex)** 로 바꾼다.
  candidates : `CAND_<mode>_<cluster_key>.json`
  review_log : `AX-PENDING_<cluster_key>.json` (+ `history[]` 최대 10회)

규율
----
* **삭제 0건.** 대체된 구 파일은 같은 트리의 `_archive_20260823/` 로 *이동*한다
  (git 이력·grep 가능성 보존).
* **멱등.** 두 번 돌려도 두 번째는 아무것도 옮기지 않는다(신 규약 파일명은
  `^AX-PENDING_[0-9a-f]{12}\\.json$` / `^CAND_<mode>_[0-9a-f]{12}\\.json$` 로 판별).
* `candidates/archived_promoted/` 는 손대지 않는다(승격 완료 아카이브).
* 이관 전/후 건수를 **둘 다** 출력한다 — "몇 건이 있었고 몇 건이 남았나"를
  사후에 재구성할 수 없으면 이관이 맞았는지 확인할 방법이 없다.

실행: python 02_Infrastructure/axiom/migrate_candidates_v9.py [--dry-run] [--project-dir DIR]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone

ARCHIVE_DIRNAME = "_archive_20260823"
NEW_PENDING_RE = re.compile(r"^AX-PENDING_[0-9a-f]{12}\.json$")
NEW_CAND_RE = re.compile(r"^CAND_[A-Za-z0-9_]+_[0-9a-f]{12}\.json$")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cluster_extractor import _cluster_key, _cluster_key_full  # noqa: E402


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8-sig") as fh:
            return json.load(fh)
    except Exception:
        return None


def _long(p: str) -> str:
    """Windows MAX_PATH(260) 회피용 확장길이 접두 — 절대경로 + 역슬래시일 때만 유효."""
    if os.name != "nt":
        return p
    ap = os.path.abspath(p).replace("/", "\\")
    return ap if ap.startswith("\\\\?\\") else "\\\\?\\" + ap


def _shortened(arch_dir: str, name: str) -> str:
    """경로가 그래도 길면 이름을 결정적으로 줄인다(내용 손실 없음 · 원명 복원 가능).

    ★이 분기가 필요했던 이유 자체가 이번 이관의 동기다 — 구 규약 파일명이 길어
      `_archive_20260823/` 아래로 옮기면 260자를 넘겨 `shutil.move` 가 WinError 3 으로
      죽는다(실측 266자). 이관 도구가 같은 결함에 걸리면 이관이 중간에 멈춘다.
    """
    stem, ext = os.path.splitext(name)
    import hashlib
    h = hashlib.sha1(name.encode("utf-8")).hexdigest()[:8]
    room = 250 - len(os.path.abspath(arch_dir)) - len(ext) - len(h) - 4
    room = max(room, 16)
    return f"{stem[:room]}__{h}{ext}"


def _relocate(src: str, arch_dir: str, dry: bool) -> str:
    """구 파일을 _archive_20260823/ 로 **이동**(삭제 아님). 동명 충돌 시 접미 번호."""
    os.makedirs(arch_dir, exist_ok=True)
    base = os.path.basename(src)
    dst = os.path.join(arch_dir, base)
    n = 1
    while os.path.exists(dst):
        stem, ext = os.path.splitext(base)
        dst = os.path.join(arch_dir, f"{stem}__{n}{ext}")
        n += 1
    if dry:
        return dst
    try:
        shutil.move(src, dst)
        return dst
    except OSError:
        pass
    try:                                     # ① 확장길이 경로로 재시도 (원명 보존)
        shutil.move(_long(src), _long(dst))
        return dst
    except OSError:
        pass
    dst2 = os.path.join(arch_dir, _shortened(arch_dir, os.path.basename(dst)))
    shutil.move(_long(src), _long(dst2))     # ② 그래도 안 되면 결정적 단축명
    print(f"  [archive] 경로 길이 회피 — {os.path.basename(src)} -> {os.path.basename(dst2)}")
    return dst2


# ════════════════════════════════════════════════════════════════════════════
# 1) candidates — 날짜 id → 해시 id
# ════════════════════════════════════════════════════════════════════════════
def migrate_candidates(cand_dir: str, dry: bool) -> dict:
    files = sorted(glob.glob(os.path.join(cand_dir, "CAND_*.json")))
    arch = os.path.join(cand_dir, ARCHIVE_DIRNAME)
    renamed = skipped = archived_dup = unreadable = already = 0
    # (target_name -> (mtime, src)) — 같은 클러스터가 여러 구 파일로 흩어져 있으면
    #   가장 최신 1건만 승계하고 나머지는 아카이브(지식은 아카이브에 남는다).
    plan: dict = {}
    id2key: dict = {}
    for f in files:
        d = _load(f)
        if not isinstance(d, dict):
            unreadable += 1
            continue
        sup = d.get("supporting_l_codes") or []
        if not sup:
            unreadable += 1
            continue
        mode = d.get("research_mode") or "unknown"
        key = _cluster_key(sup)
        old_id = d.get("candidate_id") or os.path.splitext(os.path.basename(f))[0]
        id2key[old_id] = key
        target = f"CAND_{mode}_{key}.json"
        if os.path.basename(f) == target and NEW_CAND_RE.match(target):
            already += 1
            # 이미 신 규약 — 필드만 보강(멱등: 값이 같으면 안 씀)
            plan.setdefault(target, []).append((os.path.getmtime(f), f, d, mode, key, sup))
            continue
        plan.setdefault(target, []).append((os.path.getmtime(f), f, d, mode, key, sup))

    for target, group in sorted(plan.items()):
        group.sort(key=lambda t: t[0], reverse=True)      # 최신 우선
        mtime, src, d, mode, key, sup = group[0]
        dst = os.path.join(cand_dir, target)
        payload = dict(d)
        payload["candidate_id"] = os.path.splitext(target)[0]
        payload["cluster_key"] = key
        payload["l_code_set_sha"] = _cluster_key_full(sup)
        payload.setdefault("cluster_label",
                           f"{mode}_{d.get('polarity') or 'unknown'}")
        payload["promotable"] = len(set(sup)) >= 2
        payload.setdefault("created_at",
                           datetime.fromtimestamp(mtime, timezone.utc).isoformat(timespec="seconds"))
        payload.setdefault("last_seen", payload["created_at"])
        changed = (payload != d) or (os.path.basename(src) != target)
        if not changed:
            skipped += 1
        else:
            if not dry:
                with open(dst, "w", encoding="utf-8") as fh:
                    json.dump(payload, fh, indent=2, ensure_ascii=False)
            if os.path.basename(src) != target:
                _relocate(src, arch, dry)
            renamed += 1
        for _m, extra_src, _d, _mo, _k, _s in group[1:]:
            _relocate(extra_src, arch, dry)
            archived_dup += 1
    return dict(before=len(files), renamed=renamed, unchanged=skipped,
                already_new_scheme=already, archived_duplicates=archived_dup,
                unreadable=unreadable, id2key=id2key)


# ════════════════════════════════════════════════════════════════════════════
# 2) review_log — 클러스터당 1파일 + history[]
# ════════════════════════════════════════════════════════════════════════════
def _known_clusters(project_dir: str, cand_dir: str) -> list:
    """(mode, cluster_key, l_codes) 알려진 클러스터 전수 — candidates + DIST 카드."""
    seen: dict = {}
    for f in glob.glob(os.path.join(cand_dir, "CAND_*.json")):
        d = _load(f)
        if isinstance(d, dict) and (d.get("supporting_l_codes") or []):
            seen[_cluster_key(d["supporting_l_codes"])] = (
                d.get("research_mode") or "unknown", d["supporting_l_codes"], d.get("candidate_id"))
    dd = os.path.join(project_dir, "qepm", "memory", "axioms", "distilled")
    for f in glob.glob(os.path.join(dd, "DIST-*.json")):
        d = _load(f)
        if isinstance(d, dict) and d.get("cluster_key") and (d.get("supporting_l_codes") or []):
            seen.setdefault(d["cluster_key"],
                            (d.get("research_mode") or "unknown", d["supporting_l_codes"],
                             d.get("candidate_id")))
    return [(v[0], k, v[1], v[2]) for k, v in seen.items()]


def _build_id2key(project_dir: str, cand_dir: str, base: dict) -> tuple:
    """구 candidate_id -> cluster_key 사전 + 접미(tail) 매칭표.

    구 review_log 는 supporting_l_codes 를 안 들고 있어 그 자체로는 클러스터를 알 수 없다.
    되짚는 축이 둘이다:
      ① 정확 id 일치 — 현재 candidates + DIST 카드가 보존한 candidate_id.
      ② **접미 일치** — 구 id 는 `CAND_<날짜>_<mode>_<family>_<polarity>_<정렬 L-code 3개>`
         형태라 날짜/family 만 달라진 같은 클러스터가 흔하다. L-code 자체에 '_' 가 들어가
         토큰 분해는 모호하므로, 알려진 클러스터의 `"_".join(sorted(l_codes)[:3])` 를
         **문자열 접미로 정확 대조**한다(가장 긴 일치 우선 — 짧은 접미의 우연 일치 방지).
    """
    id2key = dict(base)
    tails: list = []
    for mode, key, l_codes, cid in _known_clusters(project_dir, cand_dir):
        if cid:
            id2key.setdefault(cid, key)
        tail = "_".join(sorted(l_codes)[:3])
        if tail:
            tails.append((len(tail), tail, mode, key))
    tails.sort(reverse=True)   # 긴 접미 우선
    return id2key, tails


def _resolve_key(cid: str, id2key: dict, tails: list):
    """구 candidate_id → cluster_key. 순서 = 정확 id → mode-정합 접미 → **유일** 접미."""
    if not cid:
        return None
    if cid in id2key:
        return id2key[cid]
    for _n, tail, mode, key in tails:
        if cid.endswith("_" + tail) and ("_" + mode + "_") in cid:
            return key
    # 2026-04 이전 id 는 mode 토큰 자체가 없다(`CAND_20260417_defense_negative_L-136_L-140`).
    #   그 경우만 mode 조건을 뺀 접미 대조를 허용하되 **후보가 정확히 1개일 때만** 채택한다
    #   — 모호하면 해석하지 않고 아카이브로 보낸다(틀린 병합보다 미해석이 낫다).
    for _n, tail, _mode, _key in tails:
        if cid.endswith("_" + tail):
            hits = {k for _m2, t2, _md2, k in tails if t2 == tail}
            if len(hits) == 1:
                return next(iter(hits))
            return None
    return None


def _logged_at(rec: dict, path: str) -> str:
    v = rec.get("logged_at") if isinstance(rec, dict) else None
    if isinstance(v, str) and v.strip():
        return v.strip()
    return datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def migrate_review_log(rl_dir: str, id2key: dict, tails: list, dry: bool) -> dict:
    files = sorted(glob.glob(os.path.join(rl_dir, "AX-PENDING_*.json")))
    legacy = [f for f in files if not NEW_PENDING_RE.match(os.path.basename(f))]
    already = len(files) - len(legacy)
    arch = os.path.join(rl_dir, ARCHIVE_DIRNAME)
    groups: dict = {}
    unresolved: list = []
    for f in legacy:
        d = _load(f)
        cid = (d or {}).get("candidate_id")
        if not cid:
            # 내용 판독 불가 → 파일명에서 구 id 복원 시도 (`AX-PENDING_<id>_<YYYYMMDD>...`)
            stem = os.path.splitext(os.path.basename(f))[0][len("AX-PENDING_"):]
            cid = re.sub(r"_\d{8}(_\d{6})?$", "", stem)
        key = None
        if isinstance(d, dict) and isinstance(d.get("cluster_key"), str):
            key = d["cluster_key"]
        else:
            key = _resolve_key(cid, id2key, tails)
        if not key:
            unresolved.append(f)
            continue
        groups.setdefault(key, []).append((f, d if isinstance(d, dict) else {}))

    written = 0
    for key, items in sorted(groups.items()):
        items.sort(key=lambda t: _logged_at(t[1], t[0]))          # 오래된 → 최신
        newest_path, newest = items[-1]
        history: list = []
        for p, rec in items:
            for h in (rec.get("history") or []):                   # 이미 history 를 가진 판본 승계
                if isinstance(h, dict):
                    history.append({"logged_at": h.get("logged_at"),
                                    "weighted_score": h.get("weighted_score"),
                                    "failing_hurdles": h.get("failing_hurdles") or []})
            history.append({"logged_at": _logged_at(rec, p),
                            "weighted_score": rec.get("weighted_score"),
                            "failing_hurdles": rec.get("failing_hurdles") or []})
        history = history[-10:]                                    # cap 10
        payload = dict(newest)
        payload["cluster_key"] = key
        payload["history"] = history
        payload["migrated_from"] = [os.path.basename(p) for p, _ in items]
        payload["migration_note"] = (
            "v9 이관 20260823: review_log 를 클러스터당 1파일로 접음. 구 파일은 삭제하지 않고 "
            f"{ARCHIVE_DIRNAME}/ 로 이동(이력·grep 보존).")
        dst = os.path.join(rl_dir, f"AX-PENDING_{key}.json")
        if not dry:
            with open(dst, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2, ensure_ascii=False)
        for p, _ in items:
            if os.path.abspath(p) != os.path.abspath(dst):
                _relocate(p, arch, dry)
        written += 1

    for f in unresolved:
        _relocate(f, arch, dry)

    return dict(before=len(files), legacy=len(legacy), already_new_scheme=already,
                clusters_written=written, unresolved_archived=len(unresolved))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir",
                    default=os.environ.get("QVEST_PROJECT_DIR")
                    or os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT")
                    or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    ap.add_argument("--dry-run", action="store_true", help="판정만 출력하고 파일 무변경")
    args = ap.parse_args()
    root = args.project_dir
    cand_dir = os.path.join(root, "qepm", "memory", "axioms", "candidates")
    rl_dir = os.path.join(root, "qepm", "memory", "axioms", "review_log")
    if not os.path.isdir(cand_dir) or not os.path.isdir(rl_dir):
        print(f"[migrate_v9] 대상 디렉터리 부재: {cand_dir} / {rl_dir}", file=sys.stderr)
        return 2

    n_cand_before = len(glob.glob(os.path.join(cand_dir, "CAND_*.json")))
    n_rl_before = len(glob.glob(os.path.join(rl_dir, "AX-PENDING_*.json")))
    print(f"[migrate_v9] BEFORE  candidates={n_cand_before}  review_log(AX-PENDING)={n_rl_before}"
          f"{'  (dry-run)' if args.dry_run else ''}")

    c = migrate_candidates(cand_dir, args.dry_run)
    print(f"[migrate_v9] candidates: 개명/보강 {c['renamed']} · 무변경 {c['unchanged']} · "
          f"이미 신규약 {c['already_new_scheme']} · 중복 아카이브 {c['archived_duplicates']} · "
          f"판독불가 {c['unreadable']}")

    id2key, tails = _build_id2key(root, cand_dir, c["id2key"])
    r = migrate_review_log(rl_dir, id2key, tails, args.dry_run)
    print(f"[migrate_v9] review_log: 구규약 {r['legacy']} → 클러스터 파일 {r['clusters_written']} · "
          f"이미 신규약 {r['already_new_scheme']} · 미해석 아카이브 {r['unresolved_archived']}")

    n_cand_after = len(glob.glob(os.path.join(cand_dir, "CAND_*.json")))
    n_rl_after = len(glob.glob(os.path.join(rl_dir, "AX-PENDING_*.json")))
    n_arch_c = len(glob.glob(os.path.join(cand_dir, ARCHIVE_DIRNAME, "*.json")))
    n_arch_r = len(glob.glob(os.path.join(rl_dir, ARCHIVE_DIRNAME, "*.json")))
    print(f"[migrate_v9] AFTER   candidates={n_cand_after}  review_log(AX-PENDING)={n_rl_after}"
          f"  |  아카이브 candidates={n_arch_c}  review_log={n_arch_r}  (삭제 0건)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
