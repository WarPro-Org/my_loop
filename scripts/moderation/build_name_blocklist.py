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
]
# English words that are insults/sexual terms, so the ordinary-word filter must keep them.
KEEP_WHOLE_WORD = [
    "shit", "fuk", "ass", "arse", "tit", "tits", "cum", "fag", "fags", "twat", "cock", "cocks", "anal", "anus",
    "boob", "boobs", "clit", "coon", "coons", "kike", "milf", "nazi", "nazis", "nude", "orgy",
    "poof", "poon", "quim", "sex", "smut", "spic", "wank", "horny", "pedo", "rape", "rapist",
    "homo", "dyke", "heil", "penis", "pussy", "chink", "gook", "tranny", "negro", "semen",
    "sperm", "orgasm", "nipple", "vulva", "clitoris", "rectum", "raping", "incest",
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

EXPLICIT = {"ł": "l", "ø": "o", "đ": "d", "ß": "ss", "æ": "ae", "œ": "oe", "ı": "i", "ð": "d",
            "þ": "th", "ſ": "s", "ƒ": "f", "ħ": "h", "ŧ": "t", "ƀ": "b", "ƶ": "z", "ǥ": "g"}
FOLD_VECTORS = pathlib.Path(__file__).resolve().parent / "fold_vectors.json"
LEET = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}
SEPARATORS = re.compile(r"[ \-_'’.]+")
LATIN_FOLDED = re.compile(r"^[a-z0-9]+$")
MIN_SUBSTRING_LENGTH = 7  # shorter foreign words hide inside names (pipari, jajko, poppen)
MIN_WHOLE_WORD_LENGTH = 3


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
    render(sorted(severe), sorted(whole - severe), sorted(exceptions))
    print(f"severe={len(severe)} whole={len(whole - severe)} exceptions={len(exceptions)}")


def render(severe: list[str], whole: list[str], exceptions: list[str]) -> None:
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
    /// <summary>Blocked when found anywhere in the folded, separator-stripped name.</summary>
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
}}
""", encoding="utf-8")


if __name__ == "__main__":
    main()
