# Waypoint analytics (PostHog)

This app uses **PostHog** for the pre‑paywall product funnel and **RevenueCat**
for subscriptions. PostHog sees the whole journey (onboarding → first question →
answer → paywall → trial); RevenueCat only sees the paywall and after. The two
are stitched by a shared identity so one user is one funnel.

Everything is routed through a single wrapper: `lib/services/analytics_service.dart`.
There are **no** raw PostHog calls anywhere else, and every call is guarded so
analytics can never crash the app — if PostHog fails to init (or no key is
supplied), the app runs normally with analytics silently off.

---

## 1. Setup — where the keys go

Keys are injected with `--dart-define` and read in `lib/constants.dart`
(`kPostHogApiKey`, `kPostHogHost`, `kInternalBuild`). **No key is hardcoded in
committed source.**

- **PostHog project key:** `phc_...` (publishable client key).
- **PostHog host:** `https://us.i.posthog.com` (already the default).

### Dev (VS Code / F5)
`.vscode/launch.json` is **gitignored**. Copy the template and fill in real keys:

```
cp .vscode/launch.json.example .vscode/launch.json
```

Then set the values in `--dart-define=POSTHOG_API_KEY=...` etc. The dev template
also sets `WAYPOINT_INTERNAL=true`, so your dev builds are excluded from the
funnel automatically.

### Terminal / CI / release builds
Pass the same defines on the build command, e.g.:

```
flutter run   --dart-define=ANTHROPIC_API_KEY=... --dart-define=POSTHOG_API_KEY=phc_...
flutter build ipa --dart-define=ANTHROPIC_API_KEY=... --dart-define=POSTHOG_API_KEY=phc_...
flutter build appbundle --dart-define=ANTHROPIC_API_KEY=... --dart-define=POSTHOG_API_KEY=phc_...
```

Do **not** put `WAYPOINT_INTERNAL=true` on release builds. If you omit
`POSTHOG_API_KEY`, analytics just stays off — the app still works.

> Native auto‑init is disabled (`com.posthog.posthog.AUTO_INIT=false` in
> `AndroidManifest.xml` and `Info.plist`) precisely so the key comes from the
> dart‑define and never has to be hardcoded in a native file. Init happens once
> in `main()` before `runApp`.

---

## 2. The six events

| Event | Fires when | Properties |
|---|---|---|
| `onboarding_step_viewed` | each onboarding screen appears | `step`: `welcome` \| `first_question` \| `denomination` \| `trial` |
| `onboarding_completed` | user finishes onboarding and enters the app (purchase **or** "Maybe later") | — |
| `first_question_asked` | user submits their first‑ever real Companion question (once per user, ever) | — |
| `answer_received` | the Companion response stream finishes | `success`: `true` on clean completion, `false` on stream error |
| `paywall_viewed` | the RevenueCat paywall is presented (onboarding, chat limit, search gate, or Settings) | — |
| `trial_started` | a purchase completes at the paywall (app‑fired; see §5) | — |

Notes:
- Onboarding's "aha moment" **is** the first real question now — the old
  scripted John 1:1 / Logos autoplay is gone. Page 2 (`first_question`) lets the
  user tap a felt‑need prompt or type their own question and get a real,
  personalized streamed answer within the first ~30–60 seconds. Because it's a
  genuine user‑initiated question, it fires the *same* `first_question_asked`
  and `answer_received` events chat_screen fires later for a returning user —
  there's no separate onboarding-only variant. Whichever happens first (onboarding
  or a later chat message) is what the funnel sees; `first_question_asked` is
  guarded to fire once per user, ever, so it can't double-count.
- That first onboarding exchange is also saved as the start of the Companion
  conversation (`kChatSessionKey`), so it's still there when the user opens the
  Companion tab — the "aha" doesn't disappear when onboarding ends.
- Denomination selection now happens **after** the first question, framed as
  optional ("Want this tuned to your tradition?") — it never blocks progress.
- The **denomination value is never sent** (religious affiliation is sensitive).
  We only record that the `denomination` step was viewed.
- PostHog **lifecycle autocapture** is on (`Application Opened`, sessions), which
  gives you D1/D7 retention for free — no extra events needed.

---

## 3. Build the funnel (PostHog UI)

Product → **Funnels** → New. Add these steps **in order**:

1. `onboarding_completed`
2. `first_question_asked`
3. `answer_received`
4. `paywall_viewed`
5. `trial_started`

Set the conversion window to something generous (e.g. 7 days) since a user may
return before starting a trial. Optionally add `onboarding_step_viewed` (broken
down by `step`) as a separate insight to see *which* onboarding screen loses
people — filter that insight/funnel by the `step` property.

**Always** apply the internal filter below, or your own testing pollutes the numbers.

---

## 4. Exclude internal devices (you + your mom)

Internal devices tag every event with the property **`is_internal = true`**. Two
ways to turn it on:

- **Dev builds:** `--dart-define=WAYPOINT_INTERNAL=true` (already in the dev
  launch template).
- **Any device, incl. an App Store / TestFlight install:** open **Settings** and
  **tap the version label ("Waypoint • Version …") 7 times.** A snackbar confirms
  "Internal mode ON". Tap 7 more times to turn it off. This persists on that
  device. Do this once on your phone and once on your mom's phone.

**Filter it out in PostHog:** on every funnel/insight add a filter:

> `is_internal` **is not** `true`

(Equivalent: `is_internal` is not set.) This drops all internal events cleanly.

---

## 5. Identity & the RevenueCat ↔ PostHog stitch

- PostHog generates and persists its own **anonymous `distinct_id`**, which
  carries the entire anonymous pre‑paywall journey. We **never** reset it.
- On a successful purchase **or** restore, the app calls
  `Posthog().identify(userId: <RevenueCat app user ID>)`. This is the **same ID**
  RevenueCat's own PostHog connector keys its events on, so the anonymous journey
  and the paying identity merge into one person. Identify runs for **new payers**,
  not just restores — that's the whole point of the stitch.
- **`trial_started` source of truth is the app**, fired on a purchase result.
  A **restore** identifies but does **not** fire `trial_started` (a restore is an
  existing subscriber reinstalling, not a new trial — counting it would inflate
  conversion).

### RevenueCat → PostHog integration (you enable this in the RC dashboard)
Turn on RevenueCat's PostHog integration and set the PostHog API key + host
there. It will forward subscription lifecycle events under **its own** event
names (e.g. `rc_trial_started_event`, `rc_renewal_event`), which **do not
collide** with our `trial_started`. Use **our `trial_started`** as the funnel
step; treat RevenueCat's `rc_*` events as supplementary revenue data. The only
thing that must line up for the stitch to work is the identity — which it does,
because both sides use the RevenueCat app user ID.

---

## 6. Verify events live

1. Run the dev config (F5) or `flutter run` with the dart‑defines set.
2. In PostHog open **Activity → Live events** (real‑time).
3. Because dev is internal, either (a) watch for events tagged
   `is_internal=true`, or (b) temporarily remove `WAYPOINT_INTERNAL` to see them
   "clean". Walk the path and confirm each appears with a **consistent
   `distinct_id`**:
   - launch → onboarding: `onboarding_step_viewed{step:welcome}`.
   - tap a felt‑need prompt (or type a question) on page 2 →
     `onboarding_step_viewed{step:first_question}`, then `first_question_asked`
     (first time only) and `answer_received{success:true}` once the streamed
     reply finishes.
   - advance through denomination (`step:denomination`) and trial (`step:trial`).
   - finish onboarding → `onboarding_completed`.
   - trigger a paywall → `paywall_viewed`; complete a (sandbox) purchase →
     `trial_started`, and the `distinct_id` becomes the RevenueCat app user ID.

If the funnel ever shows a cliff to zero at one step, suspect identity first —
but this build never resets the anonymous ID and only ever `identify`s to the RC
ID, so the anonymous → paid handoff is continuous.

---

## 7. App Store privacy nutrition labels — what to declare

With this configuration PostHog does **not** collect the IDFA (the iOS SDK
removed all AdSupport references), so **no App Tracking Transparency prompt is
required** and nothing here is "Data used to track you."

Data types now collected (all for **App Functionality / Analytics**, **not linked
to a real‑world identity**, **not** used for tracking):

| Apple data type | What / why |
|---|---|
| **Identifiers → Device ID / User ID** | PostHog's anonymous `distinct_id`; and the RevenueCat app user ID we `identify` with after purchase |
| **Usage Data → Product Interaction** | the six funnel events + lifecycle (app opens, sessions) |
| **Purchases** | that a trial/subscription started (no card or financial data — RevenueCat/Apple handle payment) |

Also verify in your PostHog project settings whether **GeoIP** is on. PostHog can
derive **coarse location** (country/region/city) from the request IP server‑side.
If it's enabled, either declare **Coarse Location** (Analytics, not linked, not
tracking) as well, or disable GeoIP / IP storage in PostHog to avoid the
disclosure. Nothing in the app sends GPS/precise location.

> Not legal advice — declare what your build actually sends. The above matches
> the current configuration (no IDFA, no session replay, lifecycle on).
