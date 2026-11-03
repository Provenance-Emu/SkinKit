# Creator profiles on emuskins.com and in the apps

Status: draft for approval · 2026-11-03 · "Later" in [ROADMAP.md](../../ROADMAP.md), first item of SkinKit#26
Repos: `Provenance-Emu/skins` (data, bot, site), SkinKit (`SkinCatalogKit`, `SkinKitUI`), then Provenance, iFly, iCube
Companions: [`2026-11-03-follow-creators-design.md`](2026-11-03-follow-creators-design.md), [`2026-11-03-gamification-design.md`](2026-11-03-gamification-design.md)

## Why

The catalog credits about 150 distinct `author` strings across roughly 1,390 skins, and the site already builds a page per author with two or more skins (91 pages under `docs/authors/`). Those pages are thin: a name, an avatar guessed from the GitHub owner in `source`, system badges and the skin grid. There is no bio, no link to the creator's own site, Discord or tip jar, and nothing a creator can edit. In the apps the credit is a `Text("by \(entry.author ?? "Unknown")")` line (`Sources/SkinKitUI/Views/Catalog/SkinCatalogDetailView.swift:268`) that leads nowhere.

deltastyles.com, where 1,150 of our skins come from, gives each uploader a profile: handle, avatar, a short bio, social links and the list of their uploads with counts. Creators have told us (SkinKit#26) they want at least that on emuskins.com, and they want it to be theirs: claimable, editable, and removable.

The constraint that shapes everything: emuskins.com is a static GitHub Pages site with no server and no database. Profile data has to live in the repo, be edited through GitHub, and be published by the catalog build.

## What exists today (researched 2026-11-03)

**In the skins repo**

- `author` is a free string on each `skins/<system>/<slug>.json`. The deltastyles scraper takes it from the `/user/<name>` link in a listing block (`scripts/crawl_sources.py:60`); the delta-skins.github.io scraper from `data-maker`/`data-author` (`:476`); GitHub-repo crawls use the `attribution` in `sources.json` when the skin itself has none (`:515`); the submission form has an optional "Author / Credit" field (`.github/ISSUE_TEMPLATE/submit-skin.yml`). Nothing normalizes it. Slugifying all current author strings with `generate_author_pages.slugify()` produces no collisions today.
- `source` is `owner/repo` for GitHub-hosted skins and a host name (`deltastyles.com`, `delta-skins.github.io`) otherwise. No author spans two sources.
- `scripts/generate_author_pages.py` groups visible skins by the exact `author` string, skips authors with one skin (59 of them), derives a GitHub login from `source` for the avatar (`github_username_from_skins`, `author_avatar_html`), bakes the skin cards into static HTML, writes `docs/authors/<slug>.html` plus `docs/authors/index.html` sorted by skin count, and deletes pages for authors who no longer qualify. `scripts/generate_skin_pages.py:176` links a skin page to its author page only when that page exists.
- `scripts/process_optout.py` already solves "prove you are this GitHub account or control this repo" for the opt-out form: owner login match, org public membership (`GET /orgs/{org}/public_members/{login}`), or a `.emuskins-optout` file plus `/verify`. Every issue value reaches it through `env:` (`.github/workflows/optout.yml`). `blocklist.json` and `process_optout.py` are the proof that a GitHub-issue-driven bot with no backend is the house pattern.
- `docs/js/browse.js` shows the author on cards and in the modal as a quick-search button (`:1126`, `:1310`); `authorAvatarHtml()` (`:1523`) repeats the GitHub-owner guess client side.
- Some deltastyles entries credit the uploader rather than the artist: "ClearDoom by NostromoCrew01" has `author: starvingartist`. 63 names contain " by ".

**In SkinKit**

- `SkinCatalogEntry` (`Sources/SkinCatalogKit/SkinCatalogEntry.swift`) has `author: String?`, `source: String?`, `submittedBy` (null for every entry today) and decodes leniently, so new keys are safe for shipped builds.
- `SkinCatalogBrowserView` (iOS) prints `family?.creditLine ?? "by \(entry.author ?? "Unknown")"` on each card (`:642`); `TVOSSkinCatalogBrowserView` uses App Store–style rows. `Sources/SkinKitUI/Support/SafariWebView.swift` exists for opening links in-app on iOS.
- All three apps fetch `https://emuskins.com/catalog.json` first and the GitHub raw file second (`SkinCatalogService`).

**deltastyles.com.** From what we know of its profile pages: handle, avatar, a free-text bio, social links (Discord, X, Ko-fi style), and the uploader's skins with download counts. One polite probe at `https://deltastyles.com/user/aphaits` (honest User-Agent, single request) returned 404, so the exact profile URL shape is unverified; the crawler only ever sees `/user/<name>` links in listing blocks (`crawl_sources.py:60`). "At least what deltastyles offers" therefore means: avatar, display name, bio, links, socials, the skin list with counts, plus what they do not have: claim verification, variant families, and the same profile inside three apps.

## Goals

1. A creator can **claim** their author name, fill in a bio, avatar, banner, links and socials, and later edit or delete all of it, without a maintainer in the loop whenever ownership can be checked automatically.
2. emuskins.com author pages show the profile, and **every** author (one skin or fifty, claimed or not) has a page.
3. The three apps show the same profile from the store: tap the credit on a card or the detail view and get a profile sheet with the bio, links and the creator's other skins, installable from there.
4. Existing `author` strings keep working unchanged for shipped builds and for the crawler.
5. Moderation is possible with the tools we have: issue forms, labels, PR review and the build.

## Non-goals

- Accounts or logins on emuskins.com. GitHub is the identity.
- Comments, messages, or any creator-to-user channel.
- Rewriting `author` on catalog entries. It stays the display credit the crawler maintains.
- Hosting creators' own files, galleries or wallpapers. The profile links out.
- Ratings. `rating` is null on every entry and stays out of scope.

## Design

### 1. Data: `creators/<slug>.json` in the skins repo

One hand-editable file per claimed creator, next to `skins/` and `sources.json`. Generated outputs never go here. Shape:

```json
{
  "slug": "aphaits",
  "displayName": "aphaits",
  "aliases": ["aphaits"],
  "githubLogin": "aphaits",
  "bio": "GBA and DS skins with a soft hardware look. Requests on Discord.",
  "avatarURL": "https://github.com/aphaits.png",
  "bannerURL": null,
  "links": [
    { "label": "Website", "url": "https://example.com" }
  ],
  "socials": {
    "github": "aphaits",
    "discord": "aphaits",
    "bluesky": "aphaits.bsky.social",
    "kofi": "aphaits"
  },
  "claim": { "issue": 412, "method": "source", "verifiedAt": "2026-11-10" },
  "hidden": false
}
```

- `slug` is the file name and the stable id the site and apps use. It is `generate_author_pages.slugify(displayName)` at claim time and never changes afterwards, even if the display name does (renames keep URLs and follow lists working). Lowercase, `[a-z0-9-]`, 50 chars max, and never a path that differs from an existing one only by case.
- `aliases` lists the exact `author` strings in the catalog that belong to this creator. The build maps each catalog entry to a creator through this list. An alias can belong to one creator only; the validator rejects duplicates across files.
- `githubLogin` is the account that proved the claim. Only this account (or a maintainer) may change the file later.
- `bio` is plain text, 500 characters max, no Markdown or HTML. The site escapes it; the apps show it as `Text`.
- `avatarURL` and `bannerURL` are `https` URLs the creator supplies. The build fetches each once, checks it is an image under 2 MB, resizes (avatar 256×256, banner 1200×400), and publishes the result to a `creators` GitHub Release, the same mechanism `generate_thumbnails.py` uses for the `thumbnails` release. Pages and apps load the mirrored copy, never the original, so a dead or swapped origin image cannot break or vandalise a page later. GitHub avatars (`https://github.com/<login>.png`) are the default suggestion in the form.
- `links` is at most 6 `{label, url}` pairs, `https` only, labels 30 characters max. A short deny list in `scripts/creator_policy.py` rejects URL shorteners and known malware hosts.
- `socials` holds handles, not URLs, keyed by a fixed set: `github`, `discord`, `x`, `bluesky`, `mastodon` (`user@host`), `instagram`, `youtube`, `twitch`, `tiktok`, `kofi`, `patreon`, `buymeacoffee`, `deltastyles`, `reddit`. The site and apps build the URL from a table and draw the right icon. Unknown keys fail validation. Keeping handles rather than URLs is what makes socials safe to render as icons and impossible to use for arbitrary links.
- `claim` records how the profile was verified, for audit.
- `hidden: true` keeps the file but publishes nothing (moderation hold).

`scripts/skin_schema.py` gains `validate_creator(obj)` and the constants above; `scripts/validate_skin.py` or a new `scripts/validate_creator.py` runs it; `validate-pr.yml` validates changed `creators/*.json` like it validates skin JSON. `build_catalog.py --check-only` fails on alias duplicates, bad slugs, and a slug whose aliases match no catalog entry (a stale claim is allowed to exist but is reported).

### 2. What the build publishes

`build_catalog.py` reads `creators/*.json` and:

- adds `creator: "<slug>"` to each catalog entry whose `author` is in some creator's `aliases`, or whose JSON carries a hand-set `creator` (see §6). Entries with no match get `creator` derived as `slugify(author)` so the apps can always open a profile. Shipped builds ignore the key.
- writes `docs/creators.json`: `{ "version": 1, "updated": ISO date, "creators": [ ...profile objects without `claim`, plus `stats` from the gamification build and `skinIds` ... ] }`. Unclaimed authors appear too, as minimal records (`slug`, `displayName`, `aliases: [author]`, `claimed: false`, `avatarURL` = mirrored GitHub avatar when `source` gives one), so the apps have one directory to read. At about 150 creators this is tens of kilobytes.
- publishes `docs/creators/<slug>.json` per creator as well, so a page or an app can fetch one profile without the directory. Both are generated; the hand-edited source stays under `creators/`.

`catalog.json` stays one flat file and gains only the `creator` string per entry. The profile text is not inlined, which keeps the 1 MB catalog from growing with bios and lets a profile edit publish without changing 1,376 entries.

### 3. Claiming: an issue form plus the opt-out bot's verification

`.github/ISSUE_TEMPLATE/claim-profile.yml` (label `creator-claim`, title prefix "Claim profile: "):

- "Your name on EmuSkins" (required): the author string or the `emuskins.com/authors/<slug>.html` URL. Multiple names, one per line, when the catalog spells them differently.
- Display name, bio, avatar URL, banner URL, up to 6 links (`label | url` per line), socials (`key: handle` per line).
- A checkbox: "I made these skins, or I am the account that publishes them."

`.github/workflows/claim-profile.yml` runs `scripts/process_claim.py` on `issues: opened` and on `issue_comment` from the issue author (`/verify`, `/approve` handling as below). Values travel through `env:` only, like `optout.yml`. The script:

1. Parses the form. Resolves each name to the set of catalog entries with that exact `author`. Fails with a comment if a name matches nothing, or if an alias is already in another `creators/*.json`.
2. Verifies ownership, in this order, reusing `process_optout.py`'s `GitHubAPI`, `lookup_repo`, `check_account` and `check_file` (move them into a shared `scripts/github_ownership.py` so both bots use one copy):
   - **`source`**: every matched entry has `source` = `owner/repo` and the issue author is that owner (User) or a public member (Organization). This covers the registered-repo creators (LitRitt, masonkoleh, Polyphian, …), about 120 skins.
   - **`file`**: the entries come from GitHub repos the author does not own by login. The bot asks for `.emuskins-creator` containing the issue number at the root of each repo's default branch, then `/verify`.
   - **`manual`**: the entries come from deltastyles.com or delta-skins.github.io (1,261 skins, most creators). The bot labels the issue `needs-maintainer` and posts what it checked. A maintainer (someone in `CODEOWNERS`) comments `/approve`, optionally `/approve aliases: a, b` to adjust the alias list, and the bot proceeds. The maintainer matches the claimant to the deltastyles handle the way `remove-other.yml` already asks: a deltastyles profile that links back to the issue, a Discord handle, a message on the deltastyles page. A later improvement, once someone confirms the deltastyles profile URL shape, is a bot check for the issue number in the claimant's deltastyles bio, fetched through `polite_http` (one request).
3. On success: writes `creators/<slug>.json`, mirrors the images, commits to `main`, dispatches `build-catalog.yml`, comments with the page URL, labels `claimed`, closes the issue. On failure or policy hit (§5): comments and labels `needs-maintainer`.

Edits after the claim: the creator edits `creators/<slug>.json` in a PR, or refiles the form with the same names. `validate-pr.yml` accepts a change to `creators/<slug>.json` when the PR author equals that file's `githubLogin` or is a maintainer, and rejects otherwise with a comment. Deleting the file removes the profile; the author page falls back to the unclaimed rendering.

Deletion and opt-out: a creator who opts their repo out (`process_optout.py`) loses the skins, so the page prunes itself as it does today; the profile file is removed in the same run when the opt-out author equals `githubLogin`.

### 4. Website rendering

`scripts/generate_author_pages.py` changes from "group by author string" to "group by creator slug":

- Load `creators/*.json`; build `alias → slug`. Every visible author gets a page, including single-skin authors. The two-skin threshold goes away because a creator with one family of 7 variants, or one excellent skin, is still a creator; the index can still sort by activity. `generate_skin_pages.py` then always has an author page to link to.
- Hero for a claimed creator: banner (if any), avatar, display name, bio, a row of social icons built from the handle table, the `links` list, system badges, counts, and the badges from the gamification build. For an unclaimed author: today's hero plus a "Claim this page" button that opens the claim form with the name prefilled (`issues/new?template=claim-profile.yml&title=…&names=…`).
- The page `<head>` gets `<link rel="alternate" type="application/rss+xml" href="<slug>.xml">` once the follow design's per-author feed exists, and JSON-LD `Person` gains `url`, `image` and `sameAs` (the social URLs), which is what search engines use for a knowledge panel.
- `docs/authors/index.html` keeps its cards, adds the mirrored avatar and a "claimed" check mark, and sorts by most recently added skin by default (see the gamification doc on leaderboards). The count is still shown.
- `docs/js/browse.js`: the author button on cards and in the modal links to `authors/<slug>.html` instead of running a quick search; `authorAvatarHtml()` prefers the mirrored avatar from `creators.json` (loaded lazily, once) and keeps the GitHub guess as fallback.
- Share cards for author pages (`generate_share_cards.py`) use the avatar and display name, so a shared profile link previews as the person.

### 5. Moderation

- **At claim time**, `process_claim.py` enforces the schema (§1) and the policy in `scripts/creator_policy.py`: bio length, `https` only, link count, deny-listed hosts, handle shapes per social key, image size and type. A bio that matches `scripts/mature_keywords.json` (the same list `content_policy.py` uses for skins) or contains a URL is not rejected but routed to `needs-maintainer`.
- **Reports**: `report-skin.yml` gets a sibling `report-creator.yml` (label `content-report`) with the profile URL, a reason dropdown (impersonation, offensive bio or image, broken or malicious link, other) and details. Author pages carry a "Report this profile" link the way skin cards carry `report_link_html`.
- **Actions a maintainer can take**, all through PRs or direct commits to `creators/<slug>.json`: set `hidden: true` (page falls back to unclaimed, apps show the minimal profile), remove a link or image, or delete the file. Nothing needs a deploy beyond the catalog build.
- **Impersonation**: a claim is only possible with proof, and the manual path requires a maintainer. If a verified creator disputes an alias held by another profile, the maintainer moves the alias; the per-entry `creator` override (§6) settles single skins.
- **Text safety**: everything is escaped in the generator and rendered as plain `Text` in the apps. Socials are handles, never raw URLs. Images are the mirrored copies.

### 6. Migrating author strings to creator slugs

No catalog entry's `author` changes. The slug is derived, then refined:

1. **Build-time derivation** (no data change): `creator = slugify(author)` for every entry, overridden by an alias match. Verified no two current authors collapse to one slug; `build_catalog.py --check-only` keeps checking.
2. **Per-entry override**: a skin JSON may carry `"creator": "<slug>"` by hand, for the deltastyles cases where the uploader is not the artist ("ClearDoom by NostromoCrew01" credits `starvingartist`). The crawler's merge in `process_submission.save_entries` preserves existing non-null keys, so a hand-set `creator` survives re-crawls. `backfill_creators.py` can propose overrides for the 63 "… by X" names as a dry-run report, not an automatic rewrite, because some of those are game titles, not credits.
3. **Aliases absorb spelling drift**: when the same person shows up as `alek_witha_k` on deltastyles and `alekwithak` on GitHub, their claim lists both and the pages merge. The old slug's page redirects to the new one through a small static `<meta http-equiv="refresh">` page the generator writes for every alias slug that differs from the creator slug, so bookmarked `authors/<old>.html` URLs keep working.
4. **SkinKit**: `SkinCatalogEntry.creatorSlug: String?` decodes `creator`; when nil (old catalog), the app computes the same slugify locally (`SkinCreatorSlug.make(from:)`, a Swift port with a test pinning it to the Python output for the current author names), so the profile sheet works against any catalog.

### 7. In the apps: `SkinCreator` and a profile sheet

`SkinCatalogKit`:

- `SkinCreator: Decodable, Sendable, Hashable, Identifiable` with `slug`, `displayName`, `aliases`, `isClaimed`, `bio`, `avatarURL`, `bannerURL`, `links: [SkinCreatorLink]`, `socials: [SkinCreatorSocial]` (an enum with a `url` and `symbolName` per case, unknown keys dropped), `stats`, `badges` (from the gamification design), `skinIds`. Lenient decoding like `SkinCatalogEntry`.
- `SkinCreatorDirectory` (actor): fetches `https://emuskins.com/creators.json`, falls back to the raw GitHub URL, caches to disk with the catalog's cache policy, and answers `creator(for slug:)`, `creator(for entry:)` (slug, then alias, then local slugify) and `skins(by creator:, in catalog:)`. One network call per session, refreshed with the catalog.
- `SkinCatalogEntry.creatorSlug`.

`SkinKitUI`:

- `SkinCreatorProfileView` (iOS sheet, tvOS full-screen page): banner, avatar, display name with a check mark when claimed, bio, social icon row, links, the badges row, then the creator's skins as family cards reusing `SkinFamilyVariantsSection` and the existing install flow, filtered by the host app's `SkinStorePolicy` so iCube only lists what it can install. Links open in `SafariWebView` on iOS; tvOS shows the handle or URL as text (no browser).
- Entry points: the credit line on `CatalogSkinCard` and the `by …` row in `SkinCatalogDetailView` become buttons; `SkinFamily.creditLine` keeps its text. The Follow button from the follow design sits in the header.
- Unclaimed authors get the minimal profile (name, initial avatar, skins), so the sheet never dead-ends.

Apps: no app code beyond adopting the SkinKit bump, since the store views come from `SkinKitUI`. Provenance's `UITesting` demo gets a profile fixture.

## Constraints

- Static site, no server. Everything is files in the repo, GitHub Releases for images, GitHub Actions for the bot.
- `catalog.json` stays one flat file old builds can read; the only new per-entry key is `creator`.
- Crawler politeness: the bot never fetches deltastyles to verify a claim until the profile URL shape is confirmed, and then through `polite_http` with one request.
- macOS is case-insensitive: slugs are lowercase and the validator refuses two files differing only by case.
- Images are mirrored, never hotlinked (hotlink protection and swapped images both bit the thumbnail job before).

## Calls I made

- **Profiles live in `creators/<slug>.json` in the skins repo**, not in a separate data repo, a Discussions thread, or a service. The skins repo already has the bot pattern, the validators, the build, CODEOWNERS and the issue forms; a second repo would double the plumbing for 149 small files. Discussions are off on the repo and are not a data store. A service is unjustified for data that changes a few times a week.
- **Claim verification reuses `process_optout.py`'s checks**, extracted to a shared module, with a maintainer `/approve` path for deltastyles creators. Automatic for GitHub-sourced creators, human for the rest, because we cannot prove a deltastyles identity without scraping, and scraping for identity is both fragile and impolite.
- **Socials are handles, links are a short allow-listed list**, so the profile can never carry an arbitrary clickable URL dressed as a Discord icon.
- **Every author gets a page**; the two-skin threshold goes. Single-skin creators are a third of all authors.
- **`author` is never rewritten.** The slug is derived at build time and refined by `aliases` and a per-entry `creator` override.
- **The profile text is not inlined in `catalog.json`.** A separate `creators.json` keeps the catalog small and lets profile edits publish on their own.
- **tvOS shows links as text.** No browser there; a QR code is a nice-to-have left to the builder.

## Left to the builder

Visual design of the hero, the sheet and the social icon row; the exact `creators.json` field order; the share-card layout for profiles; how `process_claim.py` and `process_optout.py` share tests (`tests/test_optout.py` is the model); the Swift port of `slugify` and its fixture.

## Follow-up issues

Ready to paste. Each gets the "Later" milestone and the `See AGENTS.md` footer.

**1. Catalog: `creators/<slug>.json` schema, validation and build output**
Where: Provenance-Emu/skins: `creators/` (new), `scripts/skin_schema.py`, `scripts/creator_policy.py` (new), `scripts/build_catalog.py`, `scripts/validate_skin.py` or a new `scripts/validate_creator.py`, `.github/workflows/validate-pr.yml`, `tests/`.
Do: Define the creator file per the spec §1 (slug, displayName, aliases, githubLogin, bio, avatarURL, bannerURL, links, socials, claim, hidden) with validation and the social-handle table. `build_catalog.py` adds `creator` to each entry (alias match, then per-entry override, then slugify) and writes `docs/creators.json` plus `docs/creators/<slug>.json`, including minimal records for unclaimed authors. `--check-only` fails on duplicate aliases and case-colliding slugs. `validate-pr.yml` validates changed creator files and checks the PR author against `githubLogin`.
Depends on: nothing.
Done when: a hand-written `creators/example.json` validates, the build emits `creator` on its entries and a `creators.json` with every author, and tests cover the alias and collision rules.

**2. Bot: claim a creator profile from an issue form**
Where: Provenance-Emu/skins: `.github/ISSUE_TEMPLATE/claim-profile.yml`, `.github/workflows/claim-profile.yml`, `scripts/process_claim.py`, `scripts/github_ownership.py` (extracted from `process_optout.py`), `scripts/mirror_creator_images.py`, `tests/test_claim.py`.
Do: Per spec §3: parse the form, resolve names to catalog entries, verify by `source` ownership, `.emuskins-creator` file, or maintainer `/approve`; mirror avatar and banner to a `creators` release; write the file, commit, dispatch the catalog build, comment and close. Values through `env:` only. Route policy hits to `needs-maintainer`.
Depends on: issue 1.
Done when: a claim from a registered-repo owner completes with no human; a deltastyles claim waits for `/approve` from a CODEOWNERS member; `--dry-run` works; tests mirror `tests/test_optout.py`.

**3. Website: creator profiles on author pages, index and skin pages**
Where: Provenance-Emu/skins: `scripts/generate_author_pages.py`, `scripts/generate_skin_pages.py`, `scripts/generate_share_cards.py`, `docs/js/browse.js`, `docs/style.css`, `.github/ISSUE_TEMPLATE/report-creator.yml`.
Do: Group by creator slug; a page for every author; claimed hero with banner, avatar, bio, socials, links and a report link; unclaimed hero with "Claim this page"; redirect stubs for alias slugs; index sorted by recent activity with avatars; cards and modal link to the author page; share cards and JSON-LD `Person` with `sameAs`.
Depends on: issue 1.
Done when: `python3 scripts/generate_author_pages.py` renders a claimed and an unclaimed page from fixtures, `tests/test_share_meta.py` passes for the new pages, and Lighthouse on an author page does not drop below the Stage 2 target.

**4. SkinCatalogKit: `SkinCreator`, `SkinCreatorDirectory` and `creatorSlug`**
Where: SkinKit `Sources/SkinCatalogKit/`, `Tests/SkinCatalogKitTests/` (fixture `creators.json`).
Do: Models and directory per spec §7, lenient decoding, disk cache, emuskins.com then raw GitHub fallback, `creator(for entry:)` resolution order (slug, alias, local slugify) and a `SkinCreatorSlug` port of the Python `slugify` pinned by a fixture of the current author strings.
Depends on: issue 1 for the published shape (can start from the spec).
Done when: `xcrun swift test` passes with the fixture and an old catalog without `creator` still resolves a profile for every entry.

**5. SkinKitUI: creator profile sheet from the store (iOS and tvOS)**
Where: SkinKit `Sources/SkinKitUI/Views/Catalog/` (new `SkinCreatorProfileView.swift`), `SkinCatalogBrowserView.swift`, `SkinCatalogDetailView.swift`, `TVOSSkinCatalogBrowserView.swift`, `Previews/`.
Do: The sheet per spec §7 with the creator's skins as installable families filtered by the host policy; credit lines become buttons; links through `SafariWebView` on iOS and as text on tvOS; a minimal profile for unclaimed authors; previews and a `UITesting` fixture in Provenance.
Depends on: issue 4; the Follow button comes from the follow design's issue.
Done when: tapping a credit in all three apps opens the same profile for the same catalog, and installing from the sheet goes through the existing install path.

## Open questions

1. **Who approves deltastyles claims?** The spec says anyone in `CODEOWNERS`. Is that the right group, and is a `/approve` comment enough, or should it be a PR review on the generated file?
2. **Should a verified GitHub creator be able to claim deltastyles aliases automatically** when the deltastyles handle equals their GitHub login? It is a convenience with an impersonation edge (handles are not unique across sites). I lean no.
3. **Avatar fallback for unclaimed deltastyles authors.** Today it is a coloured initial. Mirroring deltastyles avatars would mean one request per author through `polite_http`; worth it, or wait for claims?
4. **Banner or no banner.** It is the one field that adds real page weight. Drop it from v1?
5. **Should `creators.json` be bundled into the apps** as a fallback like the sample fixtures, so the profile sheet works offline on first launch?
