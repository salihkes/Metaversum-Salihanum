#!/usr/bin/env python
"""
Download bad words lists from LDNOOBW repository
https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words

Run this script to download/update the bad words lists.
"""

import urllib.request
import json
import os

# Base URL for raw files
BASE_URL = "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/"

# Languages to download (add more as needed)
# Available: ar, cs, da, de, en, eo, es, fa, fi, fil, fr, fr-CA-u-sd-caqc, 
#            hi, hu, it, ja, kab, ko, nl, no, pl, pt, ru, sv, th, tlh, tr, zh
LANGUAGES = [
    "en",      # English
    "de",      # German
    "es",      # Spanish
    "fr",      # French
    "tr",      # Turkish
    "ru",      # Russian
    "pt",      # Portuguese
    "it",      # Italian
    "nl",      # Dutch
    "pl",      # Polish
    "ar",      # Arabic
    "zh",      # Chinese
    "ja",      # Japanese
    "ko",      # Korean
]

OUTPUT_FILE = "bad_words.json"


def download_word_list(language: str) -> list:
    """Download word list for a specific language"""
    url = f"{BASE_URL}{language}"
    print(f"  Downloading {language}... ", end="")
    
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            content = response.read().decode('utf-8')
            words = [line.strip() for line in content.split('\n') if line.strip()]
            print(f"{len(words)} words")
            return words
    except Exception as e:
        print(f"FAILED: {e}")
        return []


def main():
    print("=" * 60)
    print("LDNOOBW Bad Words Downloader")
    print("https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words")
    print("=" * 60)
    print()
    
    all_words = set()
    words_by_language = {}
    
    print(f"Downloading {len(LANGUAGES)} language(s)...")
    print()
    
    for lang in LANGUAGES:
        words = download_word_list(lang)
        if words:
            words_by_language[lang] = words
            all_words.update(words)
    
    print()
    print(f"Total unique words: {len(all_words)}")
    print()
    
    # Create the bad_words.json file
    output_data = {
        "_source": "https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words",
        "_languages": LANGUAGES,
        "_total_words": len(all_words),
        "words": sorted(list(all_words)),
        "patterns": [
            # Common leetspeak patterns
            "n+[i1!]+g+[e3]+r+",
            "f+[ua@]+[c(]+k+",
            "sh+[i1!]+t+",
            "b+[i1!]+t+ch+",
            "c+[u]+n+t+",
            "p+[u]+s+s+y+",
            "d+[i1!]+c+k+",
            "a+s+s+h+[o0]+l+e+",
        ]
    }
    
    # Save to file
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, indent=2, ensure_ascii=False)
    
    print(f"Saved to {OUTPUT_FILE}")
    print()
    
    # Also save individual language files for reference
    lang_dir = "bad_words_by_language"
    os.makedirs(lang_dir, exist_ok=True)
    
    for lang, words in words_by_language.items():
        lang_file = os.path.join(lang_dir, f"{lang}.txt")
        with open(lang_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(sorted(words)))
    
    print(f"Individual language files saved to {lang_dir}/")
    print()
    print("Done! Restart the server or use /reloadfilter to apply changes.")


if __name__ == "__main__":
    main()

