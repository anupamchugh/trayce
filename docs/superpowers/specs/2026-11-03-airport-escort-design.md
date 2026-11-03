# Trayce (Airport Escort) — MVP design

Date: 2026-11-03 · Status: approved by owner 2026-11-03 · License: MIT, public repo `trayce`

Name: **Trayce**, from *tray* (security trays) and *trace* (always the latest version of your trip).

## 0. Why this beats MakeMyTrip + WhatsApp

| Moment | MakeMyTrip + WhatsApp today | Trayce |
|---|---|---|
| Booking changed | A new PDF arrives somewhere; the old PDF stays in chat looking just as valid | Same PNR, newer issue date → the old copy is marked **stale** and the changed fields are shown |
| Several sources | MMT app, airline email, agent's WhatsApp, screenshots: four places | One trip, built from every document you share in; each fact shows which document it came from |
| No signal at the gate | MMT needs the network; WhatsApp needs scrolling | Everything is stored on the device; the boarding barcode is cropped from the airline's own PDF |
| Security | Nothing helps | A pack check done at home gives a tray plan, pinned to the Lock Screen |
| Privacy | Documents go through servers | Reading, extraction and the AI run on the iPhone (PDFKit, Vision, Foundation Models) |

Trayce doesn't replace booking. It is the one place that reconciles what MakeMyTrip, the airline and WhatsApp each sent you.

Mockups: the "Airport Escort MVP" design canvas (11 screens, 3 rows).

## 1. Problem

1. **Stale documents.** A booking PDF shared on WhatsApp keeps the old date after the booking is changed. At the airport nobody can tell which copy is true.
2. **Tray friction at security.** Laptops, power banks and liquids go into trays by guesswork; missed items mean a manual re-check.

## 2. Outcome and success criteria

An iPhone app that escorts one traveller through one departure:

| # | Criterion | How we check it |
|---|---|---|
| S1 | Sharing two PDFs for the same PNR marks the older one stale and shows the field diff. | Unit test on fixture PDFs; demo run. |
| S2 | A booking PDF or screenshot becomes a typed `Booking` on the device, with no network. | Airplane-mode demo; test with fixtures. |
| S3 | A flat-lay photo of 5 items yields a tray plan with the correct rule for each item. | Fixture photos plus a rule-table unit test. |
| S4 | Every rule shown names its source and date. | UI test. |
| S5 | The demo runs end to end on a physical iPhone running iOS 27 with Apple Intelligence; fallbacks keep it usable without it. | Manual run, recorded. |

Non-goals for the MVP: issuing boarding passes, Wallet pass signing, live gate data from airlines, any claim that a bag is "cleared", and tracking or identifying security staff.

## 3. Scope by phase

**Phase 1: Living trip pass** (screens 1–4)
- Ingest: Share Extension (PDF or image) → App Group inbox → main app. Also open-in (`CFBundleDocumentTypes` com.adobe.pdf).
- Extract:
  1. PDFKit `PDFPage.string` for PDFs that have text.
  2. Vision `RecognizeDocumentsRequest` for screenshots and rendered pages; this also returns barcodes.
  3. DataDetection `.flightNumber` and `.calendarEvent`.
  4. Regex for the PNR.
  5. Foundation Models `@Generable Booking` fills and reconciles the fields.
  The 4096-token context is handled by chunking per page.
- Supersede rule (deterministic code, not AI): same PNR + later issue date → newer wins. If the issue date is missing, use the file's received date. Older copies are kept and marked `stale`.
- Boarding mode: the barcode (PDF417/Aztec) is pulled from the airline's own document with `DetectBarcodesRequest`; we never generate one.
- Timeline: ActivityKit Live Activity with `staleDate`, plus WidgetKit home and Lock Screen widgets reading the shared SwiftData store.

**Phase 2: Bag pre-check** (screens 5–7)
- Camera flat-lay → `GenerateForegroundInstanceMaskRequest` (one mask per item) → crop.
- Labelling: Foundation Models `Attachment` image prompt (iOS 27) with a `@Generable ItemKind` enum and greedy sampling. `RecognizeTextRequest` reads mAh, Wh, V and ml.
- Tap-to-fix uses `GenerateIterativeSegmentationRequest` (iOS 27; it downloads its model before first use).
- Rule engine: a bundled `rules-IN.json` (versioned, dated, with source URLs) maps an item and its attributes to `tray`, `cabinOnly`, `checkedOnly`, `fix` or `doNotCarry`. Wh = mAh × V / 1000, with V defaulting to 3.7.
- Production path (after the MVP): `DetectContoursRequest` for item outlines and a Create ML `MLObjectDetector` run through `CoreMLRequest` if the Foundation Models labels prove unreliable.

**Phase 3: Showcase demos** (screens 8–11)
- **Markup:** PaperKit `PaperMarkupViewController` over a tray or pass photo. Strokes carry no identity. "Who drew it" comes only from a participant who chose to join a shared session (CloudKit share or SharePlay); a demo can stub this with local names.
- **Miniature:** RealityKit `RealityView` with a USDZ airliner (a free, redistributable model; to confirm) and seat and door markers.
- **Bag size:** Object Capture (`ObjectCaptureSession` → `PhotogrammetrySession`, LiDAR phones) gives the bag's outer bounds. ARKit `ARRaycastQuery` corner taps work on phones without LiDAR. Shown as approximate against the airline limit.
- **Ask Escort:** `LanguageModelSession` with Tools `getTrip`, `checkItemRule` and `mAhToWh`. The model only phrases the answer; the tools return the facts.
- Vision optical flow (`TrackOpticalFlowRequest`): not needed for the MVP. Consider it only if live camera labels jitter between frames.

## 4. Architecture

```
AirportEscort (iOS app, SwiftUI)
├─ Core (Swift package, platform-neutral, unit-tested)
│   ├─ Booking, TripDocument, SupersedeResolver      ← pure logic
│   ├─ BCBPParser                                     ← IATA boarding-pass string
│   ├─ Rules (RuleTable, ItemKind, Verdict, Wh math)  ← pure logic + rules-IN.json
├─ Extraction  (PDFKit, Vision, DataDetection, FoundationModels adapters)
├─ BagCheck    (Vision masks, FM image labelling, OCR)
├─ Showcase    (PaperKit, RealityKit, ObjectCapture, ARKit)
├─ Widgets     (WidgetKit + ActivityKit extension)
└─ ShareExtension (copies files to the App Group inbox only; no AI in the extension)
```

Data: SwiftData in an App Group container. Nothing leaves the device unless the optional flight-data adapter is turned on.

Fallbacks: when `SystemLanguageModel.default.availability != .available`, extraction falls back to regex plus DataDetection, and item labels fall back to `ClassifyImageRequest` plus manual pick.

## 5. Targets and settings

iOS only: `supportedDestinations: [iphone, ipad]`, `SUPPORTS_MACCATALYST/MAC_DESIGNED_FOR_IPHONE_IPAD/XR_DESIGNED_FOR_IPHONE_IPAD: false`, `TARGETED_DEVICE_FAMILY "1,2"`. Deployment target iOS 27. Generated with XcodeGen (`project.yml`).

## 6. External data

Apple exposes no flight-status API. Gate and terminal come from the user's documents. An optional adapter may show the aircraft position from a free public source; see section 9.

## 7. Risks

- India liquids rule (domestic vs international) is unconfirmed and may differ by airport → each rule is shown as advice with its source and date.
- Foundation Models output changes between OS versions → version the prompts and keep the facts in code and tools.
- Object Capture needs a LiDAR phone and takes minutes → it's a showcase only, with raycast fallback.
- Open source: fixtures must be synthetic (no real PNRs, names or barcodes).

## 8. Testing

- `Core`: Swift Testing for SupersedeResolver, BCBPParser, Wh math and rule lookups (TDD).
- Extraction: fixture PDFs and screenshots generated by us.
- UI: smoke test of the trip flow in the simulator. Apple Intelligence, Object Capture and camera paths are checked on device.

## 9. Flight data and 3D assets (decided)

- **Live aircraft:** adsb.lol (no key, free, ODbL v1.0, attribution in the app).
  - `GET /v2/callsign/{ICAO callsign}` for the traveller's flight.
  - `GET /v2/point/{lat}/{lon}/{nm}` for traffic near BLR or DEL.
  - Returns position, type and registration only, with no gate, terminal or delay.
- **Airports:** OurAirports `airports.csv` (public domain), bundled.
- **Not used:**
  - OpenSky: arrival and departure data are nightly only, and it now needs OAuth2.
  - AviationStack: 100 calls a month, and commercial use needs a paid plan.
  - AeroDataBox: no commercial use.
  - FlightAware Personal: personal use only.
  - The adapter is a protocol, so a paid gate/terminal source can be added later.
- **Gate, terminal and delay:** come only from the user's documents, and the screens label them as such.
- **Aircraft model:**
  - A CC BY 4.0 or CC0 glTF, converted to USDZ with Reality Converter, credited in `CREDITS.md`, with no airline livery.
  - Apple's `toy_biplane_realistic.usdz` can be loaded by URL for local testing, but it is never committed (Apple's terms forbid redistribution).
- **RealityKit on iOS:** `RealityView` plus `Entity(contentsOf:)`. `Model3D` is visionOS-only, so it isn't used.
- **Markup authorship:** PencilKit/PaperKit strokes carry no author. The app keeps a side table from element ID to author, and each author is resolved from `CKShare.Participant` when a markup session is shared.
