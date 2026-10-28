"""Write a reference subtitle and a copy shifted by two seconds, for the end-to-end sync test."""
import sys

PHRASES = [
    "The river runs beneath the bridge.", "A red bicycle waits by the gate.",
    "Please close the window before sunset.", "The library opens at nine tomorrow.",
    "Fresh bread is cooling in the kitchen.", "Our train leaves from platform seven.",
    "The old lighthouse overlooks the harbor.", "Three small birds landed on the roof.",
    "We found the missing key this morning.", "The garden needs water after the heat.",
]


def timestamp(seconds: int) -> str:
    return f"{seconds // 3600:02d}:{seconds // 60 % 60:02d}:{seconds % 60:02d},000"


def srt(offset: int, cues: int = 60) -> str:
    return "\n".join(
        f"{i + 1}\n{timestamp(4 * (i + 1) + offset)} --> {timestamp(4 * (i + 1) + offset + 2)}\n{PHRASES[i % len(PHRASES)]}\n"
        for i in range(cues)
    )


if __name__ == "__main__":
    reference, shifted = sys.argv[1:3]
    with open(reference, "w", encoding="utf-8") as f:
        f.write(srt(0))
    with open(shifted, "w", encoding="utf-8") as f:
        f.write(srt(2))
