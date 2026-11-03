# Following creators in the apps and on emuskins.com

Status: draft for approval · 2026-11-03 · "Later" in [ROADMAP.md](../../ROADMAP.md), second item of SkinKit#26
Repos: SkinKit (`SkinCatalogKit`, `SkinKitManager`, `SkinKitUI`), Provenance, iFly, iCube (entitlements), `Provenance-Emu/skins` (catalog dates, site, feeds)
Companions: [`2026-11-03-creator-profiles-design.md`](2026-11-03-creator-profiles-design.md) (defines the creator slug this design follows), [`2026-11-03-gamification-design.md`](2026-11-03-gamification-design.md)

## Why

Once a creator has a profile, the obvious next ask is "tell me when they publish something". Today a user who likes a creator's work has to remember the name and search for it; the store's "recent" sort is global, and the website's "New since last visit" only fires for the 23 entries that carry `lastUpdated`.

There is no server, so there is no account to attach a follow list to and nobody to send a push notification. The design has to deliver a useful "new from the people you follow" view using only what the client can store and what the static catalog can say about when a skin appeared.

## What exists today (researched 2026-11-03)

**Dates in the catalog.** Of 1,392 entries, 23 have `lastUpdated`, 113 have `submittedAt`, and none has a reliable "added to catalog" date. `lastUpdated` comes from GitHub release metadata or the crawler when available; deltastyles entries, the majority, have neither. `SkinSortOption.recent` (`Sources/SkinKitUI/Models/SkinCatalogService+Queries.swift:10`) sorts on `lastUpdated`, so it is effectively undefined for 98% of the catalog. The website's `isNewSkin()` (`docs/js/browse.js:85`) has the same gap. Any "new from creators you follow" shelf is only as good as this date, so fixing it is part of this design.

**Preferences in SkinKit.** `DeltaSkinPreferences` (`Sources/SkinKitManager/DeltaSkinPreferences.swift`) persists per-system, per-game and alt-layout picks in `UserDefaults` under `com.provenance.deltaskin.*` keys, with an injectable `UserDefaults` for tests. `SkinStoreInstalledRecord` (`SkinStoreInstalledRecord.swift`) maps catalog ids to installed skin identifiers per app (`iFly(defaults:)`, `iCube(rootURL:)`), and `SkinCatalogSidecar` (`SkinSystemOverrideRegistry.swift`) writes `<stem>.skinmeta` next to installed skins so Provenance's CloudKit and iCloud Drive syncers carry them.

**iCloud in the apps.** Provenance's entitlements enable `CloudDocuments` and a ubiquity container; iFly's enable `CloudKit` and the container `iCloud.com.joemattiello.iCube` on iOS, tvOS and Catalyst (iFly shares iCube's container). None of the three apps has the `com.apple.developer.ubiquity-kvstore-identifier` entitlement, and no app or SkinKit source references `NSUbiquitousKeyValueStore`. Key-value store sync is available but not yet switched on anywhere.

**Website.** `docs/js/browse.js` already keeps per-viewer state in `localStorage`: favourites under `prov-favs` (a JSON array of skin ids), last visit under `prov-last-visit`, and the mature opt-in. `scripts/generate_rss.py` writes one site-wide `docs/feed.xml` of the 20 most recently updated skins, sorted by the same sparse `lastUpdated`. Author pages are static HTML with the catalog subset baked in as `window.CATALOG_OVERRIDE`.

## Goals

1. **Follow a creator in any of the three apps** from the profile sheet, the store card or the detail view, and see a "New from creators you follow" shelf in the store that is accurate about what is new.
2. **Follows survive reinstalls and reach the user's other devices** without us running anything.
3. **No notifications by default.** The shelf is the feature; an opt-in local notification can come later and must not need a server.
4. **The website gets the equivalent**: a follow button, a "From creators you follow" section, and a per-creator RSS feed for anyone who wants a real subscription.
5. **Every catalog entry gets a trustworthy "added" date**, which also fixes the existing recent sort and the site's new-since-last-visit markers.

## Non-goals

- Push notifications, email, or a feed that needs a server.
- Syncing the website's follow list with the apps. There is no identity to join them on. The two lists are independent, with an export/import hand-off (see §5).
- Follower counts shown anywhere. The data lives on devices; nobody can count it, and we do not want to.
- Following systems, tags or games. Creators only, for now.

## Design

### 1. `addedAt` in the catalog

`build_catalog.py` gains `addedAt` per entry: the ISO date the entry's JSON file was first committed to the skins repo, from `git log --diff-filter=A --follow --format=%cI -- <path>`, read once per build and cached in a generated `added-dates.json` so the build does not walk git history for every skin file every run (only new files are looked up). `build-catalog.yml` sets `fetch-depth: 0` for that step. For a repack that fans one zip into several files sharing a `groupId`, each member keeps its own first-commit date, which is what the user would want ("new variant added").

`effectiveDate` for sorting and "new" is `lastUpdated ?? addedAt`. `SkinCatalogEntry` decodes `addedAt`; `SkinSortOption.recent` and `browse.js`'s `isNewSkin()` switch to the effective date. Old builds ignore the key.

This is the one catalog change in the design and the only reason a follow shelf can say "new" for a deltastyles skin.

### 2. `CreatorFollowStore` in `SkinKitManager`

```swift
@MainActor public final class CreatorFollowStore: ObservableObject {
    public static let shared = CreatorFollowStore()
    @Published public private(set) var follows: [String: CreatorFollow] // keyed by creator slug
    public func isFollowing(_ slug: String) -> Bool
    public func follow(_ slug: String)
    public func unfollow(_ slug: String)
    public func markShelfSeen()   // records the newest effectiveDate shown
    public init(defaults: UserDefaults = .standard, cloud: KeyValueCloudStore? = .ubiquitousIfEntitled)
}

public struct CreatorFollow: Codable, Sendable, Hashable {
    public var slug: String
    public var followedAt: Date
    public var unfollowedAt: Date?        // tombstone; present means "not following"
}
```

- Persisted as JSON under `UserDefaults` key `com.provenance.skinkit.creatorFollows.v1`, following the `DeltaSkinPreferences` key style, with an injectable `UserDefaults` for tests. A second key, `com.provenance.skinkit.creatorFollows.shelfSeen.v1`, holds the newest `effectiveDate` the user has looked at on the shelf.
- **Sync through `NSUbiquitousKeyValueStore`** when the host app has the entitlement. The store writes the same JSON blob under the same key and observes `didChangeExternallyNotification`. Merge is per slug, last writer wins on `max(followedAt, unfollowedAt)`; tombstones mean an unfollow on the iPad is not undone by the iPhone's stale copy. **Tombstones are kept indefinitely.** The map holds at most one record per creator (about 150), so there is nothing to garbage-collect, and any expiry window would let a device that stayed offline longer than the window resurrect the follow when it merged its old `followedAt` against a missing tombstone. A `follow()` after an unfollow simply sets a newer `followedAt` and clears `unfollowedAt`; the record is never deleted. At about 150 creators the blob is a few kilobytes against KVS's 1 MB and 1,024-key limits, and KVS needs no schema, no CloudKit container setup and no conflict UI, which is why it beats a CloudKit record type or a file in the iCloud Drive container.
- `KeyValueCloudStore` is a small protocol over `NSUbiquitousKeyValueStore` so tests can inject an in-memory one, and so an app without the entitlement (or a tvOS build where KVS is unavailable to that target) runs local-only without a code path change.
- Each app adds `com.apple.developer.ubiquity-kvstore-identifier` to its entitlements, with the value `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`. iFly and iCube already share one iCloud container; whether they should share one KVS identifier too (so a follow in iFly shows in iCube) is an open question below. Provenance's free, App Store, Mini and JB builds each need the line in their own entitlements file.

### 3. The shelf and the filter in the store

`SkinCatalogKit` gets a pure function so the website logic and the Swift logic can be checked against the same fixture:

```swift
public struct SkinFollowFeed {
    public static func newEntries(
        in catalog: SkinCatalog, following: Set<String>, since: Date?,
        installed: Set<String>, policy: SkinStorePolicy
    ) -> [SkinCatalogEntry]
}
```

It returns entries whose `creatorSlug` is followed, that the host policy can install, that are not already installed, ordered by `effectiveDate` descending, and marks those newer than `since` as unseen. Families collapse to their primary through `SkinFamilyIndex`, so a 7-variant release is one card.

`SkinCatalogBrowserView` (iOS) shows a **"New from creators you follow"** shelf above the system sections when the user follows at least one creator, with an unseen count badge and a "See all" that applies a **Following** filter chip (next to the existing system and device filters). `TVOSSkinCatalogBrowserView` gets the same as a horizontal row at the top. When the user follows nobody, nothing is shown; the empty state lives in the profile sheet ("Follow to see new skins here"). Opening the shelf calls `markShelfSeen()`.

**Follow button** placement: the header of `SkinCreatorProfileView` (from the profiles design), a small heart-less "Follow"/"Following" toggle on the credit row of `SkinCatalogDetailView`, and a long-press action on `CatalogSkinCard`. Deliberately not on every card face, which would turn the store into a social feed.

### 4. Notifications: none by default

The shelf is the notification. The app does not ask for notification permission on behalf of this feature.

If later demand warrants it, the design permits one opt-in path that needs no server: a `BGAppRefreshTask` (iOS only) that fetches `catalog.min.json` (518 KB) at most once a day, runs `SkinFollowFeed.newEntries`, and posts **one** local notification summarising the count ("3 new skins from creators you follow") when it is non-zero. Off by default, a single switch in the app's skin settings, never per creator, never for badges or anything else. tvOS has no user notifications and gets nothing. This is a follow-up issue, not part of the first delivery, and it should wait until the shelf has shipped and someone asks.

### 5. The website

- **Follow list in `localStorage`** under `prov-follows`, a JSON array of creator slugs, next to `prov-favs`. Helpers mirror `getFavs()/saveFavs()/toggleFav()` in `docs/js/browse.js`. The author page hero gets a Follow toggle (static HTML with the slug in a `data-creator` attribute; `browse.js` wires it), and the modal's author row gets the same toggle. The home page gets a **"From creators you follow"** section above the system sections, built client-side from the catalog the page already loads, with the same `effectiveDate` ordering and `prov-last-visit` for the "new" dot. No followers, nothing leaves the browser.
- **Export and import** so the list is not trapped: "Copy follow link" produces `https://emuskins.com/?follow=aphaits,litritt`, and loading a URL with `?follow=` offers to add those creators. That is also the hand-off from web to app: the author page's follow link opens in Safari on iOS; an app URL scheme (`provenance://follow/<slug>` and the equivalents) is listed as an open question because registering schemes is per app and the apps may prefer universal links.
- **RSS per creator.** `scripts/generate_rss.py` is refactored into `build_feed(skins, title, description, self_url, max_items)` and `generate_author_pages.py` calls it to write `docs/authors/<slug>.xml` for every creator, 20 items each, ordered by `effectiveDate`, with the thumbnail as enclosure (the existing site feed already does this). Each author page's `<head>` gets `<link rel="alternate" type="application/rss+xml">` so feed readers discover it from the page URL. The site-wide `feed.xml` keeps its path. Sitemap excludes feeds. This gives anyone who wants a real subscription one without us building notifications, and feed readers already handle the "new since I last looked" problem.
- An **OPML export** of the viewer's followed feeds ("Subscribe to these in your reader") is a few lines of JS over `prov-follows` and is in scope for the website issue.

### 6. Privacy

Follows are a preference, not an event. Nothing is sent to emuskins.com or GitHub when a user follows someone; the apps already fetch the whole catalog, so following changes no request pattern. There is no follower count because there is nothing to count. The KVS blob is in the user's own iCloud account.

## Constraints

- No server, no account. Follow lists live in `UserDefaults` plus iCloud KVS (apps) and `localStorage` (web).
- `catalog.json` stays one flat file; the only new key is `addedAt`.
- The shelf must not download anything extra beyond the catalog and `creators.json` the profile design adds.
- GitHub Pages: feeds are static files written by the same build that writes author pages.

## Calls I made

- **iCloud key-value store, not CloudKit records or a synced file.** KVS is the right size for a set of slugs, needs one entitlement line per app and no schema or container work, and merges with a few lines of last-writer-wins code. CloudKit would need a record type, a container per app and conflict handling; a `follows.json` in `Documents/DeltaSkins/` would ride Provenance's existing syncers but iFly and iCube have no such syncer.
- **`addedAt` from git history, computed at build time.** It is the only honest "new" date for deltastyles entries. It costs a `fetch-depth: 0` checkout and a cached lookup; it also fixes the existing recent sort and the site's new-since-last-visit, which are broken for most of the catalog today.
- **No notifications in v1, and never push.** The shelf answers the question. A local, once-a-day, opt-in summary is specified so a later issue does not have to redesign, but it is not scheduled.
- **Web and app follow lists stay separate**, connected by a `?follow=` link and OPML, because joining them would need an identity we have decided not to have.
- **RSS per creator is generated by the author-page pass**, reusing the existing feed code, rather than a separate script, so a creator's feed and page always agree.

## Left to the builder

The shelf's card size and the unseen badge; where the Following chip sits in the filter sheet; the tvOS row's focus behaviour; the KVS protocol's exact shape and its tests; the OPML template; whether `added-dates.json` is committed or an Actions cache.

## Follow-up issues

**1. Catalog: `addedAt` from first commit, and `effectiveDate` for recent sorts**
Where: Provenance-Emu/skins: `scripts/build_catalog.py`, a generated `added-dates.json`, `.github/workflows/build-catalog.yml` (`fetch-depth: 0`), `docs/js/browse.js` (`isNewSkin`), `scripts/generate_rss.py` ordering, `tests/test_build_catalog.py`; SkinKit `Sources/SkinCatalogKit/SkinCatalogEntry.swift`, `Sources/SkinKitUI/Models/SkinCatalogService+Queries.swift` (`.recent`).
Do: Add `addedAt` per entry from `git log --diff-filter=A`, cached, with a one-time backfill; sort recents and the site feed by `lastUpdated ?? addedAt`; decode `addedAt` in SkinKit and use it for `.recent`.
Depends on: nothing.
Done when: every catalog entry has `addedAt`, the build does not re-walk history for unchanged files, the store's Recent sort orders deltastyles skins sensibly, and tests cover the backfill.

**2. SkinKitManager: `CreatorFollowStore` with iCloud key-value sync**
Where: SkinKit `Sources/SkinKitManager/CreatorFollowStore.swift`, `KeyValueCloudStore.swift` (new), `Tests/SkinKitManagerTests/CreatorFollowStoreTests.swift`; entitlements in Provenance (`Provenance/Provenance/*.entitlements`), iFly (`iFly/iFly/*.entitlements`), iCube.
Do: Per spec §2: `UserDefaults` persistence under `com.provenance.skinkit.creatorFollows.v1`, tombstoned per-slug merge, `NSUbiquitousKeyValueStore` mirror behind a protocol, external-change observation, local-only when unentitled. Add `com.apple.developer.ubiquity-kvstore-identifier` to each app.
Depends on: the profiles design's `creatorSlug` (its issue 4) for the slug source; can be built against the spec.
Done when: `xcrun swift test` covers follow, unfollow, merge, re-follow after unfollow, and a replica offline for a year losing to a tombstone, with an in-memory cloud store, and a follow on one device appears on a second signed into the same iCloud account for at least one app.

**3. SkinKitUI: "New from creators you follow" shelf, Following filter, Follow button**
Where: SkinKit `Sources/SkinCatalogKit/SkinFollowFeed.swift` (new), `Sources/SkinKitUI/Views/Catalog/SkinCatalogBrowserView.swift`, `TVOSSkinCatalogBrowserView.swift`, `SkinCatalogDetailView.swift`, `SkinCreatorProfileView.swift`, `Tests/SkinCatalogKitTests/SkinFollowFeedTests.swift`.
Do: The pure feed function per spec §3 (followed, installable, not installed, family-collapsed, ordered by `effectiveDate`, unseen marking); the shelf with an unseen badge and `markShelfSeen()`; the Following chip; Follow toggles in the profile header and detail credit row; tvOS row.
Depends on: issues 1 and 2; the profiles design's issue 5 for the sheet.
Done when: all three apps show the same shelf for the same catalog and follow set, the badge clears when the shelf is opened, and the feed function has fixture tests shared in spirit with the website's.

**4. Website: follow list, "From creators you follow" section, per-creator RSS, OPML**
Where: Provenance-Emu/skins: `docs/js/browse.js`, `docs/index.html`, `scripts/generate_author_pages.py`, `scripts/generate_rss.py` (refactor to `build_feed`), `scripts/generate_sitemap.py` (exclude feeds), `tests/test_browse_index.py`, `tests/test_site_urls.py`.
Do: `prov-follows` in `localStorage` with toggles on author pages and in the modal; the home-page section; `?follow=` import and "Copy follow link"; `docs/authors/<slug>.xml` per creator with `<link rel="alternate">` in the page head; OPML export of followed feeds.
Depends on: issue 1 (dates); the profiles design's issue 3 (pages keyed by slug).
Done when: following on an author page adds a section to the home page, every author page advertises a valid RSS feed that a reader picks up, and `?follow=a,b` round-trips.

**5. (Deferred) Opt-in daily local notification for followed creators**
Where: SkinKit `Sources/SkinKitManager/` (a `BGAppRefreshTask` helper), each app's `Info.plist` (`BGTaskSchedulerPermittedIdentifiers`) and skin settings.
Do: Per spec §4: off by default, iOS only, one fetch of `catalog.min.json` a day, one summary notification when the feed is non-empty. Do not start until the shelf has shipped and users ask.
Depends on: issue 3.
Done when: with the switch on, a device receives at most one notification a day and none when nothing is new; with the switch off, no permission prompt is ever shown.

## Open questions

1. **One KVS identifier for iFly and iCube?** They share an iCloud container already. Sharing follows between them is probably what a user expects; sharing with Provenance is not possible across teams anyway.
2. **App URL schemes for `?follow=`.** Should the author page offer "Follow in Provenance / iFly / iCube" links? Which schemes or universal links do the apps register today?
3. **Should the shelf also surface updates** (an existing followed skin whose `lastUpdated` moved) or only new entries? Updates are rare in the data; new-only is simpler.
4. **Is `addedAt` from the first commit acceptable for the backfill**, given the repo's history starts well after many deltastyles skins were published? It is "added to EmuSkins", not "published", and the UI should say so.
5. **Commit `added-dates.json` or keep it in an Actions cache?** Committing is simpler and auditable; it adds one generated file to the never-hand-edit list.
