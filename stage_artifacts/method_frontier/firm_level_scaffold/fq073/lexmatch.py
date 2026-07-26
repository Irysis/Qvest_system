#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
lexmatch.py — 한국어 substring 오탐을 막는 경계-인지 사전 매처 (공용 모듈).

배경(실사고): 경계 없는 substring 매칭이 '참**고로**'→고로(HS7208 철강),
'**시너**지'→시너(HS3814 신너)를 만들어 네이버가 '철강 열연 평판'으로 매핑됨.
동일 실패 모드가 이 저장소의 하버스터 `_infer_family`에서도 적발된 바 있음
(word-boundary 근본수리, 2026-07-18).

규칙:
  L-guard : 모든 한글 시작 키워드 앞에 (?<![가-힣A-Za-z0-9]) — '참고로'의 '고로' 차단
  R-guard : RIGHT_GUARD 목록(실측 충돌 확인분)에만 (?![가-힣]) — '시너지'의 '시너' 차단
            ※ 전면 R-guard는 '열연'→'열연강판' 같은 정상 합성어를 죽이므로 채택하지 않음
  BLOCK   : 어떤 가드로도 구제 안 되는 키워드는 사전에서 제거
"""
import re, json

# 실측 충돌 확인 후 우측 경계를 강제하는 키워드 (collision_report.json 근거)
RIGHT_GUARD = set()
# 구제 불가로 제거하는 키워드
BLOCKED = set()


def load_guards(path):
    global RIGHT_GUARD, BLOCKED
    try:
        g = json.load(open(path, encoding="utf-8"))
        RIGHT_GUARD = set(g.get("right_guard", []))
        BLOCKED = set(g.get("blocked", []))
    except FileNotFoundError:
        pass


SHORT_KOR_MAX = 3   # 한글 음절 <=3 이면 substring 충돌 위험 → L-guard 적용


def compile_kw(kw):
    """키워드 원문 → 경계 가드가 적용된 컴파일 정규식 (BLOCKED면 None).

    L-guard를 '짧은 키워드'에만 거는 이유: 한국어는 띄어쓰기를 자주 생략하므로
    긴 키워드(4음절+)는 '차량용전력반도체'처럼 토큰 중간에 오는 정상 사례가 많다.
    여기에 L-guard를 걸면 recall이 크게 깎인다. 반면 2~3음절은 '참고로'의 '고로'처럼
    다른 단어에 우연히 포함될 확률이 높아 L-guard가 순이득이다(collision_quick.json 실측).
    """
    if kw in BLOCKED:
        return None
    pat = kw

    # (A) 순수 ASCII 토큰(약어)은 **ASCII 경계**로 감싼다.
    #     실측 충돌: or[GAN]ization / busin[ess] / insta[lled] / O[LED] 가 각각
    #     GaN(216건)·ESS·LED 로 오탐. \b 를 쓰면 'LED조명'·'TV용'처럼 한글이 뒤에
    #     붙는 정상 용례까지 죽으므로(한글도 \w) ASCII-only lookaround를 쓴다.
    if re.fullmatch(r"[A-Za-z0-9]+", kw):
        return re.compile(r"(?<![A-Za-z0-9])" + pat + r"(?![A-Za-z0-9])", re.I)

    # (B) 짧은 한글 키워드는 왼쪽 경계 가드 (참[고로] 류 차단)
    n_kor = len(re.findall(r"[가-힣]", kw))
    if re.match(r"^[가-힣]", kw) and 0 < n_kor <= SHORT_KOR_MAX:
        pat = r"(?<![가-힣A-Za-z0-9])" + pat
    if kw in RIGHT_GUARD:
        pat = pat + r"(?![가-힣])"
    return re.compile(pat, re.I)


def build(lexicon):
    """{code: {desc,w,kw[]}} → {code: (w, [(kw, regex)], desc)}"""
    out = {}
    for code, v in lexicon.items():
        if code.startswith("_"):
            continue
        pats = []
        for kw in v["kw"]:
            c = compile_kw(kw)
            if c is not None:
                pats.append((kw, c))
        out[code] = (v["w"], pats, v["desc"])
    return out


def score(txt, compiled, collect_hits=False):
    """텍스트 → {code: 점수}. collect_hits면 (점수, {code:{kw:n}}) 반환."""
    sc, hits = {}, {}
    for code, (w, pats, _d) in compiled.items():
        n, h = 0, {}
        for kw, rx in pats:
            k = len(rx.findall(txt))
            if k:
                n += k
                h[kw] = k
        if n:
            sc[code] = n * w
            if collect_hits:
                hits[code] = h
    return (sc, hits) if collect_hits else sc


TOKEN = re.compile(r"[가-힣A-Za-z0-9]+")


def enclosing_tokens(txt, rx, limit=6):
    """매치를 포함하는 최대 토큰들 — substring 충돌 진단용."""
    out = []
    for m in rx.finditer(txt):
        s, e = m.span()
        ls = s
        while ls > 0 and TOKEN.match(txt[ls - 1]):
            ls -= 1
        le = e
        while le < len(txt) and TOKEN.match(txt[le]):
            le += 1
        out.append(txt[ls:le])
        if len(out) >= limit:
            break
    return out
