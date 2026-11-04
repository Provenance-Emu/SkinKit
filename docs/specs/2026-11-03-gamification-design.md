# Gamification for creators and users

Status: draft for approval · 2026-11-03 · "Later" in [ROADMAP.md](../../ROADMAP.md), third item of SkinKit#26
Repos: `Provenance-Emu/skins` (creator stats and badges, computed in Actions), SkinKit (`SkinCatalogKit`, `SkinKitManager`, `SkinKitUI`) for display and the on-device user side
Companions: [`2026-11-03-creator-profiles-design.md`](2026-11-03-creator-profiles-design.md), [`2026-11-03-follow-creators-design.md`](2026-11-03-follow-creators-design.md)

## Why

Creators put real hours into skins and get a name on a card. A profile (first design) gives them a place; this design gives that place something to say: how far their work has travelled, how much of the catalog they cover, and a few earned badges that mean something. Users, in turn, get a quiet record of what they have tried, which nudges them to explore systems and creators they have not.

The point is recognition, not competition. The failure mode of gamification in a volunteer community is a leaderboard that rewards whoever uploads the most near-duplicates. The design below is built to count the things that are hard to fake, to say nothing publicly about users, and to refuse the mechanics (rankings by volume, points, paid placement) that would change what people make.

## What exists today (researched 2026-11-03)

**`downloadCount` is not what it sounds like.** `build_catalog.py:56` (`fetch_release_download_counts`) reads the GitHub Releases API for the `thumbnails` release and takes each asset's `download_count`, keyed by the `<id>.png` name. So `downloadCount` is the number of times a skin's **thumbnail image** was fetched from GitHub, by the website, the three apps' stores, crawlers and link previews. It is a reach or impressions number, not installs. 621 of 1,392 entries have one; 752 deltastyles entries have none because their thumbnails are not on that release yet. The website shows it as "Downloads" and `SkinSortOption.popular` sorts on it. Any design that calls this "downloads" or awards badges per thousand is building on sand, and this doc stops doing that.

**Real install signals that exist:** none that reach us. The apps install from `downloadURL`, which is deltastyles, a creator's GitHub repo or our `mirror` release. Only `mirror`-hosted skins (repacks) have an asset download count that is a true download, and that is a small, biased subset. There is no telemetry, and we are not adding any.

**Creator facts the catalog does have, and that are hard to fake:** number of visible entries and of families (`groupId`), `variants` in the sidecar for single-file variants, systems covered (23 distinct codes in use), `addedAt` once the follow design lands, link health (an entry hidden by `link_health.py` is not a working skin), the `sample` and `mature` tags, and whether the creator's profile is claimed.

**User facts the apps have, on device:** installed catalog skins (`SkinStoreInstalledRecord`, `SkinCatalogSidecar`), per-system and per-game picks (`DeltaSkinPreferences.selectedSkins`, `gameSpecificSkins`), alt-layout toggles (`gameAltRepresentations`), theme picks (`DeltaSkinAppHooks.selectedThemeId(for:)`), and families (`SkinFamilyMembership`).

**The site already has a leaderboard.** `generate_author_pages.py` calls `docs/authors/index.html` an "author leaderboard sorted by skin count desc". All five of the top authors by count are deltastyles uploaders, and 60–100% of their entries are members of variant families (per-game or per-colour versions of one design). That is exactly the ranking this design wants to retire.

## Goals

1. **Creators see honest numbers** on their profile and page: releases, variants, systems, time active, reach tier, and a handful of badges, all derived from catalog facts by the build.
2. **Users get a private record**: skins installed, systems tried, creators followed, themes and alternate layouts used, families completed, with badges, computed on device and shown in the store.
3. **One badge vocabulary** shared by the website and the three apps, defined in data so a new badge is a JSON change plus assets, not three code changes.
4. **Nothing counts that can be inflated by uploading more**, and nothing public ranks people by a number.

## Non-goals, stated as what we will not do

- **No leaderboards ranked by volume or reach.** No "Top creators", no "Most downloaded", no weekly charts. The authors index sorts by recent activity (or alphabetically) with counts shown but not ranked.
- **No points, levels, XP or streaks.** Badges are earned once and kept; nothing decays, nothing asks you to come back tomorrow.
- **No paid boosts, sponsored slots or paid featured placement**, ever. `docs/featured.json` stays a maintainer's hand-picked list with a note per pick.
- **No public user profiles or user rankings.** User stats never leave the device except through the user's own iCloud.
- **No ratings or likes.** `rating` is null everywhere and a like button needs a server.
- **No badge for follower counts.** There are none to count (follow design §6).
- **No notifications for badges.**

## Design

### 1. Badge definitions: `badges.json`

A single data file, `badges.json` at the skins repo root (hand-edited, validated), defines every badge for both audiences:

```json
{
  "version": 1,
  "badges": [
    { "id": "creator.first-release", "for": "creator", "title": "First release",
      "description": "Published a skin on EmuSkins.", "symbol": "sparkles" },
    { "id": "creator.systems.5", "for": "creator", "title": "Five systems",
      "description": "Working skins for five different systems.", "symbol": "square.grid.3x3", "tier": 1 },
    { "id": "user.systems.3", "for": "user", "title": "Explorer",
      "description": "Picked a skin on three different systems.", "symbol": "map" }
  ]
}
```

`symbol` is an SF Symbol name for the apps; the website maps the same id to an inline SVG in `docs/badges/<id>.svg` (generated from a small set of hand-drawn icons; the builder decides whether to draw or reuse the system badge style). Tiered badges share a stem (`creator.systems.5`, `.10`, `.20`) and the UI shows only the highest earned. Unknown ids in a `creators.json` or on device are rendered with a generic icon and the title, so an older app build survives a new badge.

The same file is copied into `SkinCatalogKit` as a bundled resource (`Sources/SkinCatalogKit/Resources/badges.json`) so the apps can describe user badges offline; creator badges arrive with `creators.json` already labelled. A test pins the bundled copy to the repo's version so they do not drift unnoticed.

### 2. Creator stats and badges, computed in Actions

`scripts/compute_creator_stats.py` runs in `build-catalog.yml` after the catalog and before the pages, reads the built catalog plus `variants.json`, `link-health.json` and `creators/*.json`, and writes the `stats` and `badges` blocks into each record of `docs/creators.json` (and the per-creator files). Nothing is stored in the hand-edited creator file.

Counted, per creator slug, over **visible** entries only (not hidden by link health, not `sample`-tagged; `mature` entries count but are never shown as examples):

| Stat | Definition | Why this and not something else |
|---|---|---|
| `releases` | Families (`groupId`) plus ungrouped entries | A 7-variant release is one piece of work, not seven. This is the number shown first. |
| `files` | Visible entries | Shown second, smaller, so variant-heavy creators are not erased either. |
| `variantsCompleted` | Members of families with 2+ members, plus `variants` entries from the sidecar for single-file skins | Rewards finishing a set (all the Jaguar keypads; portrait and landscape) rather than one-offs. |
| `systems` | Distinct system codes, excluding `unofficial` | Breadth is hard to fake: a working skin per system is real work. |
| `dualScreen` | Entries whose `variants` or health record shows two screens (DS/3DS) | Dual-screen skins are harder; worth a badge. |
| `firstAddedAt`, `lastAddedAt` | min/max `effectiveDate` (follow design §1) | Time active and recency, for the index sort. |
| `reachTier` | From the sum of `downloadCount` (thumbnail fetches): 0 none, 1 ≥ 1k, 2 ≥ 10k, 3 ≥ 100k | Coarse tiers only. The number is reach, not installs, and tiers blunt both the noise and the incentive to inflate it. The raw sum is **not** published per creator. |
| `claimed` | Profile verified | A badge, and the thing that unlocks showing stats on the page prominently. |

Creator badges in v1, all derivable from the table above: `creator.first-release`; `creator.systems.{3,5,10}`; `creator.family-builder` (a family with 3+ variants); `creator.completionist` (a family covering both orientations, or the sidecar shows 2+ single-file variants); `creator.dual-screen`; `creator.veteran` (`firstAddedAt` more than a year ago and at least one entry still visible); `creator.reach.{1,2,3}` (titled "Seen by thousands" and so on, never "downloads"); `creator.claimed`; `creator.open-source` (all entries from a GitHub `source` whose repo has a license file, checked once per build through the API with the token already used for release counts). Each badge records `earnedAt` as the first build date it was true, stored in a generated `badge-dates.json` so dates stay stable across rebuilds.

Display: the author page hero shows `releases`, `systems` and the badges row; the profile sheet in the apps (`SkinCreatorProfileView`) shows the same from `SkinCreator.stats` and `.badges`. Unclaimed authors get the stats but only the `first-release` and tiered-systems badges, with a "Claim your profile to see all badges" line, which is the one gentle incentive in this design.

### 3. User stats and badges, computed on device

`SkinKitManager` gets `SkinAchievementTracker` (`@MainActor`, `ObservableObject`), a pure derivation over what the app already stores. No new events are logged; stats are recomputed from state when the tracker is asked:

| Stat | Source |
|---|---|
| `installed` | `SkinStoreInstalledRecord.load()` count (catalog installs only; sideloaded skins are not counted, which keeps the number about the store) |
| `systemsTried` | Systems with a non-default pick in `DeltaSkinPreferences.selectedSkins` |
| `gamesCustomised` | Keys in `gameSpecificSkins` |
| `themesUsed` | Skins with a `DeltaSkinAppHooks.selectedThemeId` set |
| `altLayoutsUsed` | Skins appearing in `gameAltRepresentations` |
| `familiesCompleted` | Families where every member is installed (`SkinFamilyMembership` against the catalog) |
| `creatorsFollowed` | `CreatorFollowStore.follows` without tombstones |
| `creatorsInstalledFrom` | Distinct `creatorSlug` over installed entries |

User badges in v1: `user.first-install`; `user.systems.{3,5,10}` ("Explorer", "Collector", "Completist" for systems); `user.themes.1` ("Switched a theme"); `user.alt-layout.1` ("Flipped a layout"); `user.family.1` ("Completed a set"); `user.creators.5` ("Patron of five creators"); `user.follow.1` ("Following someone"). Earned dates are stored under `UserDefaults` key `com.provenance.skinkit.achievements.v1` as `{badgeId: earnedAt}` and mirrored into the same iCloud key-value store the follow design adds, so a reinstall keeps them. Badges are never revoked (uninstalling a skin does not un-earn "Explorer"); stats are live.

Display: a **"Your skins"** card at the bottom of the store browser (iOS) and a row on tvOS, showing the live stats and earned badges, with locked badges shown greyed with their description so the goals are visible but not pushy. The same view is reachable from each app's skin settings. There is no popup when a badge is earned; the card updates. This is intentionally quieter than most apps, and it is a choice Joe can reverse per app (a `SkinKitUI` flag) without changing the data.

### 4. Anti-gaming

What the numbers reward is what people will do more of, so:

- **Count releases first, files second.** Uploading the same skin in nine colours moves `files` and `variantsCompleted`, which are honest about what happened, but `releases` and `systems`, the headline numbers, do not move.
- **Only visible, working entries count.** Link health already hides entries after two deterministic failures; hidden entries drop out of every stat. `sample`-tagged fixtures never count.
- **Reach is tiered, never raw, never per skin on the profile.** The per-entry `downloadCount` stays on skin cards as today but is relabelled "Views" on the site and in `SkinCatalogDetailView` / `statsSection`, because that is what it is. `SkinSortOption.popular` keeps working but its UI label becomes "Most viewed".
- **Thumbnail-count hygiene in the build:** ignore an entry's count when it is below 50 (bot and preview noise), and when a count rises by more than 10× between consecutive builds hold the previous value for that build and log it, the way `link_health.py`'s circuit breaker refuses a suspicious run. This is a cheap guard against someone scripting fetches of their own thumbnail.
- **Badges derive from catalog facts, never from self-report.** The claim form has no "I made 50 skins" field; there is nothing to lie on.
- **Disputes suspend badges.** A `content-report` of "Copied from another author without credit" that a maintainer upholds adds the entry id to `disputed.json`; disputed entries are excluded from stats and the creator's `reach` and `releases` recompute on the next build. Resolution removes the id.
- **Users cannot game users** because nothing about a user is public.

### 5. Where the authors index lands

`docs/authors/index.html` stops being a leaderboard: the default order is most recently added skin (`lastAddedAt`), with an A–Z toggle. Cards show the avatar, display name, `releases`, systems badges and up to three earned badges. The skin count is still visible per card. This is the only existing surface the design changes rather than adds to.

## Constraints

- Static site and no telemetry. Creator stats come from the build; user stats never leave the device except through the user's own iCloud.
- `catalog.json` is unchanged by this design; stats live in `creators.json` (profiles design §2).
- One badge vocabulary for web and apps, with unknown ids rendering gracefully in old builds.
- Honest labels: "views" or "seen", never "downloads", for the thumbnail count.

## Calls I made

- **Stop calling thumbnail fetches "downloads".** Found while reading `build_catalog.py`; everything downstream inherits the mislabel. Renaming it on the site and in the apps is in scope here because gamifying a mislabelled number would entrench it.
- **Releases, not files, are the headline count**, and the index is sorted by recency, not volume. This directly reverses the current "leaderboard by skin count" and is the decision most likely to need Joe's say, because the top of the current index changes.
- **Reach as coarse tiers, with hygiene rules, and no raw per-creator total.** Enough to be flattering at scale, too blunt to be worth gaming.
- **User badges are computed from existing state, not from a new event log.** No new storage of behaviour, nothing to sync but a small `{badge: date}` map, and no privacy surface.
- **No badge popups, no streaks, no points.** A card that fills in over time. If this proves too quiet, a per-app toast flag is cheap to add.
- **Badge definitions in one JSON file**, bundled into SkinCatalogKit with a drift test, so the site and three apps agree on names and icons.

## Left to the builder

Badge icons; the exact tier thresholds (the numbers above are starting points to tune against the real distribution once `compute_creator_stats.py` runs in dry-run on the current catalog); the "Your skins" card layout; the dry-run report format for the index reorder.

## Follow-up issues

**1. Catalog: `badges.json`, creator stats and badges in `creators.json`, honest "views" label**
Where: Provenance-Emu/skins: `badges.json` (new), `scripts/compute_creator_stats.py` (new), `scripts/build_catalog.py` (count hygiene), `badge-dates.json` and `disputed.json` (generated/maintained), `.github/workflows/build-catalog.yml`, `scripts/generate_author_pages.py` and `docs/js/browse.js` (label "Views"), `tests/test_creator_stats.py`.
Do: Per spec §1–§2 and §4: define badges in data with validation; compute `releases`, `files`, `variantsCompleted`, `systems`, `dualScreen`, dates, `reachTier`, `claimed` over visible non-sample entries; derive badges with stable `earnedAt`; apply the count floor and 10× guard; exclude `disputed.json`; relabel the thumbnail count as views on the site. Ship a `--dry-run` that prints the distribution so thresholds can be tuned.
Depends on: profiles design issue 1 (`creators.json`); follow design issue 1 (`addedAt`) for dates and veteran.
Done when: `creators.json` carries stats and badges for every creator, a dry-run report exists for the current catalog, the site says "Views", and tests cover the counting rules and the guard.

**2. Website: badges and stats on author pages; index sorted by recency**
Where: Provenance-Emu/skins: `scripts/generate_author_pages.py`, `docs/badges/*.svg` (new), `docs/style.css`, `tests/test_mature_pages.py` and `tests/test_site_urls.py` as affected.
Do: Hero stats (`releases`, `systems`) and the badges row with hover descriptions; unclaimed pages show the limited set with the claim nudge; `authors/index.html` defaults to most recent activity with an A–Z toggle, shows avatar, releases and up to three badges, no rank numbers.
Depends on: issue 1; profiles design issue 3.
Done when: a claimed and an unclaimed fixture page render the right badge sets and the index order is by `lastAddedAt`.

**3. SkinCatalogKit: badge definitions bundle, `SkinCreatorStats`, `SkinCreatorBadge`**
Where: SkinKit `Sources/SkinCatalogKit/Resources/badges.json`, `Sources/SkinCatalogKit/SkinBadge.swift` (new), `SkinCreator.swift` (stats and badges fields), `Tests/SkinCatalogKitTests/SkinBadgeTests.swift`.
Do: Decode `stats` and `badges` leniently; a `SkinBadgeCatalog` that resolves ids to title, description and symbol from the bundle and falls back to a generic badge for unknown ids; a test that the bundled file matches the skins repo's `badges.json` version in the fixture.
Depends on: issue 1 for the shape (can start from the spec); profiles design issue 4.
Done when: `xcrun swift test` passes and an unknown badge id renders a title without crashing.

**4. SkinKitManager + SkinKitUI: on-device user achievements and the "Your skins" card**
Where: SkinKit `Sources/SkinKitManager/SkinAchievementTracker.swift` (new), `Sources/SkinKitUI/Views/Catalog/SkinAchievementsCard.swift` (new), `SkinCatalogBrowserView.swift`, `TVOSSkinCatalogBrowserView.swift`, `SkinCatalogDetailView.swift` (label "Views", sort label "Most viewed"), `Tests/SkinKitManagerTests/SkinAchievementTrackerTests.swift`; each app's skin settings for the entry point.
Do: Per spec §3: derive stats from `SkinStoreInstalledRecord`, `DeltaSkinPreferences`, `DeltaSkinAppHooks`, `SkinFamilyMembership` and `CreatorFollowStore`; earned badge dates under `com.provenance.skinkit.achievements.v1`, mirrored to iCloud KVS; the card with live stats and locked/earned badges, no popups, behind a `SkinKitUI` flag for toasts defaulting off.
Depends on: issue 3; follow design issue 2 for the KVS store and follows.
Done when: installing skins on three systems earns "Explorer" in all three apps, the card shows the same stats the preferences imply, and uninstalling does not revoke a badge.

**5. Moderation: `disputed.json` and the report flow for copied work**
Where: Provenance-Emu/skins: `disputed.json`, `.github/ISSUE_TEMPLATE/report-skin.yml` (no field change; a maintainer label `disputed` drives it), `scripts/compute_creator_stats.py`, README section.
Do: A maintainer labelling a `content-report` issue `disputed` (and later `resolved`) is picked up by a small workflow that adds or removes the skin id in `disputed.json` and dispatches the build. Document the policy on the site's report page.
Depends on: issue 1.
Done when: a disputed entry drops out of its creator's stats on the next build and returns when resolved.

## Open questions

1. **Reorder the authors index by recency?** This changes who appears at the top today. Alternatives: keep count order but drop the word "leaderboard" and show releases rather than files; or alphabetical only. I recommend recency.
2. **Rename "Downloads" to "Views" now, in this project, or in a separate quick fix?** It is independent of everything else and could ship this week.
3. **Reach tiers for unclaimed creators:** show them (they are catalog facts) or hold them for claimed profiles as the one incentive? The spec shows them for everyone; only the richer badges are gated.
4. **Should iCube and iFly count systems they retarget** (N64 on the GameCube pad, MAME on the Dreamcast pad) toward "systems tried"? Counting the catalog system is simpler and consistent with the creator side.
5. **Open-source badge:** worth the per-build API calls, or drop it for v1?
