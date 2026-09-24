#!/usr/bin/env python3
"""Generate api/MyLoop.Api/Constants/NameBlocklist.g.cs (DR-002b, #190).

Terms come from LDNOOBW (CC-BY-4.0) for the Latin-script European languages that display names
accept (#189), plus a hand-curated core. Every term is emitted already *folded* with the same
pipeline as NameModeration.Fold, so the API matches folded names against folded terms directly.

Tiering (why each list exists):
  severe substrings : the hand-picked CORE, plus any LDNOOBW term of >= 7 chars that occurs inside
                      no real name (NAMES corpus) and no English word (WORDS corpus) — i.e. the
                      terms that can be matched anywhere without a Scunthorpe problem.
  whole words       : every other LDNOOBW term, matched only as a complete word of the name, minus
                      ordinary English words (am, hard, trio, ...) unless listed in KEEP_WHOLE_WORD.
  dropped           : terms that ARE a common first/last name (dick, regina, anita) — the report
                      path handles those — and identity terms (IDENTITY), which are never blocked.
  exceptions        : folded names that must never be blocked even if a tier matches.

Matching semantics the safety checks rely on (NameModeration.MatchesBlocklist):
  1. Terms are matched inside ONE word of the name, never on the whole name (under that old
     rule 2,291 first+last corpus pairs were blocked — Thomas Lutz -> "slut").
  2. Runs of tokens of at most MAX_SPELLED_OUT_TOKEN_LENGTH chars ("s-h-i-t") are joined.
     main() asserts no corpus name is that short.
  3. Two ADJACENT words are also checked as a pair, so one space cannot hide a term:
       a. their concatenation equals a severe term ("Nig Ger", "F uck", "Fuc K");
       b. one of them is a single letter and their concatenation equals a whole-word term
          ("S hit", "Shi T", "Fa G");
       c. one of them is a single letter and a severe term of at least
          MIN_SPANNING_SEVERE_TERM_LENGTH chars starts (letter first) or ends (letter last)
          their concatenation ("N iggerboy").
     A pair in JOIN_EXCEPTIONS is never checked. join_collisions() finds every corpus-name pair
     (or single letter + corpus name) these rules would refuse; generation fails unless each is
     reviewed into JOIN_EXCEPTIONS (let through) or ACCEPTED_JOIN_REFUSALS (still refused).

Sources are pinned to commits so a re-run is reproducible. Usage:
    python3 scripts/moderation/build_name_blocklist.py
"""
from __future__ import annotations

import json
import pathlib
import re
import unicodedata
import urllib.request

LDNOOBW = ("https://raw.githubusercontent.com/LDNOOBW/"
           "List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/"
           "5faf2ba42d7b1c0977169ec3611df25a3c08eb13/{lang}")
LANGS = ["en", "fr", "de", "es", "it", "pt", "nl", "pl", "sv", "da", "no", "fi", "cs", "hu", "tr"]
NAMES = [  # MIT — used only at generation time, never shipped
    "https://raw.githubusercontent.com/dominictarr/random-name/"
    "468ae50d63f1d1ecb417d1b119748df9191431e7/first-names.txt",
    "https://raw.githubusercontent.com/dominictarr/random-name/"
    "468ae50d63f1d1ecb417d1b119748df9191431e7/names.txt",
]
WORDS = ("https://raw.githubusercontent.com/dwyl/english-words/"  # Unlicense — generation only
         "20f5cc9b3f0ccc8ce45d814c532b7c2031bba31c/words_alpha.txt")

OUT = (pathlib.Path(__file__).resolve().parents[2]
       / "api/MyLoop.Api/Constants/NameBlocklist.g.cs")

# Always substring-matched, regardless of corpus hits. Each was checked against the name corpus.
# Deliberately NOT here: rapist (therapist), pussy (pussycat), penis (Penistone), cock/dick (surnames),
# shit (Harshit, Kshitij, Ashita…) and fuk (Fukuda, Fukuoka…) — those are whole-word only (#193 review).
CORE = [
    "fuck", "cunt", "nigger", "nigga", "hitler", "whore", "slut", "retard",
    "faggot", "fagot", "bitch", "bastard", "wanker", "porn", "motherfuck", "cocksuck", "asshole",
    "arsehole", "dildo", "jizz", "pedophil", "paedophil", "goebbels", "himmler", "vagina",
    "arschloch", "hurensohn", "fotze", "schlampe", "wichser", "connard", "salope", "encule",
    "putain", "cabron", "pendejo", "kurwa", "cazzo", "stronzo", "vaffanculo", "caralho",
    "klootzak",
    # Common English compounds of whole-word-only terms (shit, ass): each is corpus-safe, while
    # the bare term is not (Harshit, Cassandra). Not dickhead: "Dick Head" is a real-name pair.
    "bullshit", "horseshit", "dipshit", "shithead", "shitface", "shithole", "shitbag", "dumbass",
    "asshat", "asswipe", "douchebag",
]
# Whole-word terms added by hand: English words that are insults/sexual terms (the ordinary-word
# filter would otherwise drop them), and hate terms LDNOOBW lacks (kkk).
KEEP_WHOLE_WORD = [
    "shit", "fuk", "ass", "arse", "tit", "tits", "cum", "fag", "fags", "twat", "cock", "cocks", "anal", "anus",
    "boob", "boobs", "clit", "coon", "coons", "kike", "milf", "nazi", "nazis", "nude", "orgy",
    "poof", "poon", "quim", "sex", "smut", "spic", "wank", "horny", "pedo", "rape", "rapist",
    "homo", "dyke", "heil", "penis", "pussy", "chink", "gook", "tranny", "negro", "semen",
    "sperm", "orgasm", "nipple", "vulva", "clitoris", "rectum", "raping", "incest",
    "kkk",
]
# Non-English LDNOOBW entries that are ordinary words or fragments (fish, spider, ball, pier,
# the SEGA brand...) — the English WORDS filter cannot see them, so they are dropped by hand.
DROP_WHOLE_WORD = [
    "2gic", "aborto", "apara", "aranha", "ariano", "aso", "balle", "barmot", "barom", "battere",
    "cona", "cono", "dodel", "dombo", "dritt", "drogas", "dvda", "etron", "fava", "fing", "folle",
    "gerber", "gotte", "gotu", "guro", "hassia", "hitto", "ische", "kanen", "knor", "kunda", "kur",
    "kusi", "lort", "marha", "meuf", "mof", "molo", "monta", "moona", "mussa", "naida", "orina",
    "palen", "pano", "pesce", "pimpern", "pinak", "pinat", "pok", "popel", "raeva", "reika",
    "reva", "rov", "ryssa", "sas", "sega", "skitt", "snol", "subba", "sulin", "tanche", "teef",
    "topa", "transar", "trique", "tusan", "tussu", "xana", "zinne",
    "asbak", "balen", "beffen", "bekken", "brinca", "brutta", "casci", "dopice", "fittig", "gozar",
    "grelho", "griet", "jajco", "jajko", "jatka", "jouir", "matje", "mutta", "naakt", "nackt",
    "pallit", "pehko", "pipari", "poppen", "tavara", "tirare", "toeter", "viiksi", "wippen",
    "zuigen", "bagnarsi", "cadavere", "cerveja", "cocaina", "consolo", "goldone", "heroina",
    "infierno", "klooien", "maldito", "martillo", "montare", "patacca", "quaglia", "racista",
    "santorum", "schatje", "sinnsykt", "spagnola", "spuiten", "standje", "stootje", "torneira",
    "twinkie",
]
# Self-description is not abuse; slurs for these groups are covered above.
IDENTITY = [
    "gay", "lesbian", "bisexual", "homosexual", "heterosexual", "queer", "trans", "transsexual",
    "transgender", "sexuality", "sexual", "intersex", "travesti", "lesbica",
]
# Whole words that are real names/places containing a severe term. Matched per word, so
# "Scunthorpe United" passes too. Generation fails if a CORE term hits an uncovered name.
EXCEPTIONS = ["scunthorpe", "penistone", "slutsky", "sporn", "cazzola", "cumming", "bastardo"]

# The NAMES corpus is Anglo-heavy; these cover players the beta actually has (Bangalore,
# Mumbai, Delhi, Tokyo seed cities) so collisions like Harshit→"shit" are measured, not missed.
EXTRA_NAMES = [
    # South Asian
    "Harshit", "Rakshit", "Kshitij", "Nishit", "Ashit", "Dikshit", "Ashita", "Harshita",
    "Nishita", "Rakshita", "Kshitiz", "Aarav", "Vivaan", "Aditya", "Arjun", "Ishaan", "Rohan",
    "Ananya", "Diya", "Saanvi", "Aadhya", "Priya", "Pooja", "Ankita", "Shikha", "Sakshi",
    "Kumar", "Sharma", "Verma", "Gupta", "Singh", "Patel", "Reddy", "Nair", "Iyer", "Menon",
    "Chatterjee", "Banerjee", "Mukherjee", "Bhattacharya", "Deshpande", "Kulkarni", "Joshi",
    "Pandey", "Tiwari", "Mishra", "Chauhan", "Rathore", "Shekhawat", "Suresh", "Ramesh",
    "Mahesh", "Dinesh", "Rajesh", "Ganesh", "Lokesh", "Nitesh", "Hitesh", "Ritesh", "Mukesh",
    "Kamlesh", "Sunita", "Anita", "Kavita", "Lalita", "Arpita", "Shweta", "Swati", "Pankaj",
    "Fatima", "Ayesha", "Zainab", "Imran", "Farhan", "Arshad", "Ashfaq", "Mushtaq",
    # East Asian (romanised)
    "Fukuda", "Fukushima", "Fukuyama", "Fukui", "Fukuoka", "Fukumoto", "Fukuzawa", "Hitomi",
    "Takeshi", "Yuki", "Hiro", "Hiroshi", "Satoshi", "Kenji", "Sakura", "Haruki", "Shinji",
    "Shiho", "Shiori", "Kazuki", "Daisuke", "Tanaka", "Suzuki", "Watanabe", "Ito", "Kobayashi",
    "Matsumoto", "Shimizu", "Yamashita", "Ishikawa", "Nakamura", "Shun", "Chen", "Wang",
    "Zhang", "Xiao", "Zhou", "Huang", "Kim", "Park", "Choi", "Jung", "Kang", "Cho", "Yoon",
    "Nguyen", "Tran", "Pham", "Phuc", "Phuong", "Dang", "Bui",
]

# Adjacent-word pairs (matching rule 3) that are, or could be, a real person's name: never
# checked as a pair, so they pass. Folded, written "first second". Every entry must be a pair
# join_collisions() reports; one that no longer collides fails generation as stale.
JOIN_EXCEPTIONS = [
    # severe tier: plausible names, and the term is obscure or non-English
    "bird lock", "bo emelen", "bran lette", "col hoes", "deb allen", "de conner", "emmer der",
    "graf tak", "moon ade", "panta va", "per kele", "pier dola", "ramon er", "ro thoer",
    "van gare", "yarak lara", "yarak lari", "yarak tan", "b lumpkin", "k inkster", "t ringler",
    # whole-word tier: a first name + surname initial, or an initial + name
    "ana l", "chin k", "chu j", "coit o", "conn e", "debi l", "fae n", "fu k", "hu j", "ku k",
    "ku t", "lu l", "l ul", "pall e", "sik i", "suk a", "sy f", "vogel n", "wan k",
    "c agata", "c agna", "f icken", "k ike", "k utas", "m erda", "m erde", "p ede", "p uta",
    "p ute", "s let",
]
# Corpus pairs matching rule 3 still refuses on purpose: the pair reads as the term itself and
# is not a plausible real name. An affected player's remedy is the report/restore review.
ACCEPTED_JOIN_REFUSALS = [
    "b itch", "bast ard", "beaner s", "black cock", "bull dyke", "conn ard", "dry hump",
    "mari con", "nee keri", "rosy palm", "snow balling", "tongue ina", "va gina", "wan ker",
    "white power",
    "as s", "cock s", "f ag", "horn y", "mil f", "rap e", "t wat",
]

EXPLICIT = {"ł": "l", "ø": "o", "đ": "d", "ß": "ss", "æ": "ae", "œ": "oe", "ı": "i", "ð": "d",
            "þ": "th", "ſ": "s", "ƒ": "f", "ħ": "h", "ŧ": "t", "ƀ": "b", "ƶ": "z", "ǥ": "g"}
FOLD_VECTORS = pathlib.Path(__file__).resolve().parent / "fold_vectors.json"
LEET = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}
SEPARATORS = re.compile(r"[ \-_'’.]+")
LATIN_FOLDED = re.compile(r"^[a-z0-9]+$")
MIN_SUBSTRING_LENGTH = 7  # shorter foreign words hide inside names (pipari, jajko, poppen)
MIN_WHOLE_WORD_LENGTH = 3
# Mirrors GameConstants.MaxSpelledOutTokenLength (C#; NameModerationTests asserts they match).
# At 2, two-letter name parts would be joined (Si Ki -> "siki", Su Ka -> "suka",
# As Lu Ty -> "slut"), and the joinable-names check in main() fails.
MAX_SPELLED_OUT_TOKEN_LENGTH = 1
# Mirrors GameConstants.MinSpanningSevereTermLength (matching rule 3c). At 4, an initial and a
# surname form a term across the space (S Luther -> "slut", P Ornstead -> "porn", J Izzy ->
# "jizz"). At 5 the corpora give no such pair except exact matches, which are reviewed above.
MIN_SPANNING_SEVERE_TERM_LENGTH = 5
LETTERS = "abcdefghijklmnopqrstuvwxyz"


def fold(text: str) -> str:
    """Must stay identical to NameModeration.Fold (C#); NameModerationTests checks fold-stability."""
    text = unicodedata.normalize("NFC", text).lower()
    text = "".join(EXPLICIT.get(c, c) for c in text)
    text = "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")
    return "".join(LEET.get(c, c) for c in text)


def joined(text: str) -> str:
    return "".join(t for t in SEPARATORS.split(fold(text)) if t)


def fetch(url: str) -> list[str]:
    with urllib.request.urlopen(url) as response:  # noqa: S310 — pinned https sources
        return [line.strip() for line in response.read().decode("utf-8").splitlines() if line.strip()]


def check_fold_vectors() -> None:
    """The same table is asserted by NameModerationTests, so the two folds cannot drift."""
    for raw, expected in json.loads(FOLD_VECTORS.read_text(encoding="utf-8")):
        actual = fold(raw)
        if actual != expected:
            raise SystemExit(f"fold({raw!r}) = {actual!r}, expected {expected!r}")


def join_collisions(names: set[str], severe: set[str], whole: set[str]) -> set[str]:
    """Corpus-name pairs ("first second") that matching rule 3 (module docstring) would refuse."""
    hits = set()
    for term in severe:  # 3a: two names, or a letter and a name, spell the term exactly
        for i in range(1, len(term)):
            left, right = term[:i], term[i:]
            one_is_name = left in names or right in names
            both_name_or_letter = all(p in names or len(p) == 1 for p in (left, right))
            if one_is_name and both_name_or_letter:
                hits.add(f"{left} {right}")
    for term in whole:  # 3b: a letter and a name spell the term exactly
        if term[1:] in names:
            hits.add(f"{term[0]} {term[1:]}")
        if term[:-1] in names:
            hits.add(f"{term[:-1]} {term[-1]}")
    spanning = [t for t in severe if len(t) >= MIN_SPANNING_SEVERE_TERM_LENGTH]
    for name in names:  # 3c: a severe term crosses the space between a letter and a name
        for letter in LETTERS:
            if any((letter + name).startswith(t) for t in spanning):
                hits.add(f"{letter} {name}")
            if any((name + letter).endswith(t) for t in spanning):
                hits.add(f"{name} {letter}")
    return hits


def check_join_collisions(names: set[str], severe: set[str], whole: set[str]) -> None:
    exempt, refused = set(JOIN_EXCEPTIONS), set(ACCEPTED_JOIN_REFUSALS)
    if exempt & refused:
        raise SystemExit(f"pairs both exempted and refused: {sorted(exempt & refused)}")
    hits = join_collisions(names, severe, whole)
    unreviewed = sorted(hits - exempt - refused)
    if unreviewed:
        raise SystemExit("adjacent-word rules refuse these real-name pairs — add each to "
                         f"JOIN_EXCEPTIONS or ACCEPTED_JOIN_REFUSALS: {unreviewed}")
    stale = sorted((exempt | refused) - hits)
    if stale:
        raise SystemExit(f"reviewed pairs that no longer collide — remove them: {stale}")


def main() -> None:
    check_fold_vectors()
    raw_terms = {joined(t) for lang in LANGS for t in fetch(LDNOOBW.format(lang=lang))}
    names = {joined(n) for url in NAMES for n in fetch(url)} | {joined(n) for n in EXTRA_NAMES}
    words = {w.lower() for w in fetch(WORDS) if len(w) >= MIN_WHOLE_WORD_LENGTH}

    core = {joined(t) for t in CORE}
    keep = {joined(t) for t in KEEP_WHOLE_WORD}
    identity = {joined(t) for t in IDENTITY}
    dropped = {joined(t) for t in DROP_WHOLE_WORD}

    severe, whole = set(core), set()
    for term in raw_terms - core - identity - dropped:
        if not LATIN_FOLDED.match(term) or len(term) < MIN_WHOLE_WORD_LENGTH:
            continue
        if term in names and term not in keep:
            continue  # it is somebody's name — leave it to the report path
        embedded = any(term in n for n in names) or any(term in w and w != term for w in words)
        if len(term) >= MIN_SUBSTRING_LENGTH and not embedded:
            severe.add(term)
        elif term not in words or term in keep:
            whole.add(term)
    whole |= keep - severe

    exceptions = {joined(e) for e in EXCEPTIONS}
    name_hits = sorted(n for n in names - exceptions if any(t in n for t in severe))
    if name_hits:
        raise SystemExit(f"severe terms hit real names — move the term or add an exception: {name_hits}")
    joinable = sorted(n for n in names if len(n) <= MAX_SPELLED_OUT_TOKEN_LENGTH)
    if joinable:
        raise SystemExit(f"real names short enough to be joined as spelled-out letters: {joinable}")
    check_join_collisions(names, severe, whole - severe)
    render(sorted(severe), sorted(whole - severe), sorted(exceptions), sorted(JOIN_EXCEPTIONS))
    print(f"severe={len(severe)} whole={len(whole - severe)} exceptions={len(exceptions)} "
          f"join_exceptions={len(JOIN_EXCEPTIONS)}")


def render(severe: list[str], whole: list[str], exceptions: list[str],
           join_exceptions: list[str]) -> None:
    def block(items: list[str]) -> str:
        lines, line = [], "        "
        for item in items:
            piece = f'"{item}", '
            if len(line) + len(piece) > 100:
                lines.append(line.rstrip())
                line = "        "
            line += piece
        lines.append(line.rstrip())
        return "\n".join(lines)

    OUT.write_text(f"""// <auto-generated>
// Generated by scripts/moderation/build_name_blocklist.py — do not edit by hand; edit the
// script's lists and re-run it. Terms are stored pre-folded (see NameModeration.Fold).
//
// Contains terms derived from "List of Dirty, Naughty, Obscene, and Otherwise Bad Words"
// by LDNOOBW contributors (https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words),
// licensed CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Filtered and re-tiered.
// </auto-generated>
using System.Collections.Frozen;

namespace MyLoop.Api.Constants;

/// <summary>Display-name blocklist tiers (DR-002b, #190). Matched by NameModeration.</summary>
public static class NameBlocklist
{{
    /// <summary>Blocked when found inside one folded word of the name (see NameModeration).</summary>
    public static readonly FrozenSet<string> SevereSubstrings = new[]
    {{
{block(severe)}
    }}.ToFrozenSet(StringComparer.Ordinal);

    /// <summary>Blocked only when a whole word of the folded name equals the term.</summary>
    public static readonly FrozenSet<string> WholeWords = new[]
    {{
{block(whole)}
    }}.ToFrozenSet(StringComparer.Ordinal);

    /// <summary>Folded words that are never blocked (real names/places containing a severe term).</summary>
    public static readonly FrozenSet<string> Exceptions = new[]
    {{
{block(exceptions)}
    }}.ToFrozenSet(StringComparer.Ordinal);

    /// <summary>Adjacent folded word pairs ("deb allen") never checked as a pair: real names.</summary>
    public static readonly FrozenSet<string> JoinExceptions = new[]
    {{
{block(join_exceptions)}
    }}.ToFrozenSet(StringComparer.Ordinal);
}}
""", encoding="utf-8")


if __name__ == "__main__":
    main()
