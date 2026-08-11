# Major Releases

Forward-looking planning ledger for major releases — one block per release, minimal fields, blank
line between blocks. Marathon plans and other forward planning cross-reference this doc for
target release names/dates; it is not a history of what shipped (that's CHANGELOG.md — lessons
learned belong there at ship time, not duplicated here). Contract lives in PROJECT/PDDA.md ->
"RELEASES.md — release ledger". Add new fields only when a real need shows up.

## This file is OPTIONAL — read this before proposing an edit to it

RELEASES.md is an **optional planning aid**. It is not a required artifact, not a checklist, and
not something to keep topped up. An empty file, a stale file, or no file at all are all valid
states — `pdda.sh releases` skips a missing file and never blocks.

**Do not proactively offer to fill it in, populate it, bring it current, or add a release that has
already shipped.** Do not treat a sparse file as an incomplete one. Edit it only when an operator
explicitly asks for release *planning*.

**What earns a block.** Being worth *planning toward* — a named arc with a theme, usually carrying a
target date and a milestone. If the only thing that can go in `Description:` is a restatement of what
changed, it belongs in CHANGELOG.md and nowhere else. The test is the theme, not the paperwork:
`Target Date:` and `Milestone:` are optional and their absence never disqualifies a block.

**`Iterations:` reserves a band of version numbers** that are reserved and deliberately not
enumerated. Versions inside a band ship freely and are recorded in CHANGELOG.md only; they never get
a block here — except the band's own owner, whose `Release:` is the band's low end and which keeps
its block by construction. Any other version inside an existing band is already accounted for, so a
block for it is a duplicate — `pdda.sh releases` warns on exactly that. If a band runs out, widen it;
promote to the next release only if the work became a new arc.

Release: 0.1.0
Iterations: 0.1.0-0.1.4
Status: Draft
Target Date:
Codename: n/a
Milestone:
Description: EXAMPLE — replace this with your first real release, or delete this block once real entries exist below.
GH_URL:
Front-door reviewed:
Shakedown reviewed:
License file:
