# Trayce MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A buildable, open-source iOS 27 demo app that unifies booking documents into one current trip, plans security trays from a photo, and shows the Apple-framework showcase screens.

**Architecture:** The facts live in a platform-neutral `TrayceCore` Swift package (pure logic, `swift test` on macOS). The iOS app adds adapters for PDFKit, Vision, Foundation Models, PaperKit, RealityKit, ObjectCapture, ActivityKit and WidgetKit. AI only extracts fields and phrases answers; Core decides supersession and rules.

**Tech Stack:** Swift 6, SwiftUI, XcodeGen, Swift Testing, iOS 27 SDK (Xcode 27.2).

**Spec:** `docs/superpowers/specs/2026-11-03-airport-escort-design.md`

## Global Constraints

- iOS only: `supportedDestinations: [iphone, ipad]`; `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` all `false`; `TARGETED_DEVICE_FAMILY "1,2"`; deployment target iOS 27.0.
- Bundle id prefix `com.alcor.trayce`; App Group `group.com.alcor.trayce`.
- No real PNRs, names or barcodes in the repo: fixtures are synthetic.
- Every rule carries `source` (URL) and `asOf` (date); copy says "advice", never "cleared".
- Gate, terminal and delay come only from documents; adsb.lol data is position/type only, credited (ODbL).
- No Apple `toy_biplane` in the repo; the plane is built from RealityKit primitives.
- Wh = mAh × V / 1000, V defaults to 3.7.

## Review Focus

1. Two documents for the same PNR where the newer one has no issue date → fall back to `receivedAt`; test `resolverFallsBackToReceivedAt`.
2. Two different PNRs on the same flight → they stay separate trips; test `differentPNRsStaySeparate`.
3. Power bank label with Wh printed instead of mAh → use the Wh value directly; test `whLabelWins`.
4. Text with no PNR → the parser returns nil rather than a half-filled booking; test `parserRejectsTextWithoutPNR`.
5. Device without Apple Intelligence → the regex parser and manual item pick still work (manual check on the simulator, which has no model).

---

### Task 1: Project scaffold + TrayceCore models and resolver

**Files:** `project.yml`, `Packages/TrayceCore/Package.swift`, `Sources/TrayceCore/{Booking,TripDocument,SupersedeResolver}.swift`, `Tests/TrayceCoreTests/SupersedeResolverTests.swift`, `LICENSE` (MIT), `.gitignore`

**Interfaces — Produces:**
- `struct Booking: Codable, Hashable, Sendable { pnr: String; carrier: String?; flightNumber: String; origin: String; destination: String; departure: Date; seat: String?; gate: String?; terminal: String?; passenger: String?; issuedAt: Date? }`
- `enum DocumentSource: String, Codable { whatsapp, mail, files, camera, sample }`
- `struct TripDocument: Codable, Identifiable, Hashable { id: UUID; fileName: String; source: DocumentSource; receivedAt: Date; booking: Booking; barcodePayload: String? }`
- `struct FieldChange: Hashable { field: String; old: String; new: String }`
- `struct Trip: Identifiable { id: String /*pnr*/; current: TripDocument; stale: [TripDocument]; changes: [FieldChange] }`
- `enum SupersedeResolver { static func trips(from: [TripDocument]) -> [Trip] }`

- [ ] Tests: `newerIssueDateWins` (14 Nov doc issued 28 Oct vs 16 Nov doc issued 2 Nov → current departure 16 Nov, one stale, changes contain field "Date"), `resolverFallsBackToReceivedAt`, `differentPNRsStaySeparate`, `identicalDocsProduceNoChanges`.
- [ ] Run `swift test --package-path Packages/TrayceCore` → FAIL, implement, → PASS. Commit.

### Task 2: Text parser and BCBP parser

**Files:** `Sources/TrayceCore/{BookingTextParser,BCBPParser}.swift`, tests for each.

**Produces:** `enum BookingTextParser { static func parse(_ text: String, issuedFallback: Date?) -> Booking? }`; `struct BoardingPassData { passengerName, pnr, origin, destination, carrier, flightNumber, dayOfYear: Int, seat, sequence: String }`; `enum BCBPParser { static func parse(_ payload: String) -> BoardingPassData? }`.

- [ ] Tests: `parsesSampleETicket` (fixture text with "PNR: X7K2LM", "6E 2134", "BLR", "DEL", "16 Nov 2026 07:40", "Issued: 02 Nov 2026" → matching fields), `parserRejectsTextWithoutPNR`, `parsesM1Payload` (synthetic `M1DOE/JANE            EX7K2LM BLRDEL6E 2134 320Y012C0041 100` → seat "12C", dayOfYear 320, sequence "0041"), `rejectsShortPayload`.
- [ ] Red → green → commit.

### Task 3: Security rules

**Files:** `Sources/TrayceCore/{ItemKind,RuleTable}.swift`, `Resources/rules-IN.json`, tests.

**Produces:** `enum ItemKind: String, Codable, CaseIterable { laptop, tablet, powerBank, cable, liquid, aerosol, lighter, blade, other }`; `struct ItemObservation { kind: ItemKind; mAh: Double?; volts: Double?; wattHours: Double?; millilitres: Double? }`; `enum Verdict: Hashable { tray(Int), cabinOnly(String), stayInBag, fix(String), doNotCarry(String) }`; `struct RuleTable { static func india() -> RuleTable; func verdict(for: ItemObservation) -> Verdict; let source: URL; let asOf: String }`; `func wattHours(mAh: Double, volts: Double = 3.7) -> Double`.

- [ ] Tests: `twentyKmAhIs74Wh`, `whLabelWins`, `powerBankUnder100WhCabinOnly`, `powerBankOver160WhDoNotCarry`, `liquidOver100mlIsFix`, `lighterDoNotCarry`, `laptopGetsTray1`.
- [ ] Red → green → commit.

### Task 4: App shell, store, trip screens (spec screens 1–4)

**Files:** `Trayce/App/{TrayceApp,TripStore}.swift`, `Trayce/Trip/{TripTodayView,ImportFlow,ChangesView,BoardingView}.swift`, `Trayce/Extraction/{DocumentReader,BookingExtractor}.swift`, `Trayce/Resources/Samples/*.pdf` (generated synthetic PDFs), `Info.plist` document types `com.adobe.pdf`, `public.image`.

- `TripStore` (`@Observable @MainActor`) persists `[TripDocument]` as JSON in the App Group container and exposes `trips` via `SupersedeResolver`.
- `DocumentReader.read(url:) async throws -> (text: String, barcode: String?, barcodeImage: CGImage?)` uses PDFKit text first, then Vision `RecognizeDocumentsRequest` plus `DetectBarcodesRequest` on a rendered page.
- `BookingExtractor.extract(text:) async -> Booking?` uses a Foundation Models `@Generable` struct when `SystemLanguageModel.default.availability == .available`, else `BookingTextParser`.
- "Load sample trip" button imports both synthetic PDFs, so the stale flow works in the simulator.
- [ ] `xcodegen && xcodebuild -scheme Trayce -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → BUILD SUCCEEDED; launch, tap sample, see "Date changed". Commit.

### Task 5: Bag check (spec screens 5–7)

**Files:** `Trayce/Bag/{BagCheckView,ItemSegmenter,ItemLabeler,TrayPlanView}.swift`, `Trayce/Widgets/` (Live Activity attributes shared).

- `ItemSegmenter.crops(from: CGImage) async throws -> [CGImage]` uses `GenerateForegroundInstanceMaskRequest`.
- `ItemLabeler.label(_ crop: CGImage) async -> ItemObservation` combines a Foundation Models image `Attachment` with a `@Generable` kind, `RecognizeTextRequest` numbers for mAh/Wh/V/ml, and a manual picker fallback.
- `TrayPlanView` groups verdicts and has "Pin to Lock Screen", which starts `Activity<TrayceActivityAttributes>`.
- [ ] Build passes; the sample flat-lay image yields a list. Commit.

### Task 6: Widgets + Live Activity extension

**Files:** `TrayceWidgets/{TrayceWidgetsBundle,TripWidget,TripLiveActivity}.swift`, `Shared/TrayceActivityAttributes.swift`.

- [ ] Build passes with the extension embedded. Commit.

### Task 7: Showcase (spec screens 8–11)

**Files:** `Trayce/Showcase/{MarkupView,PlaneView,BagMeasureView,AskView,AskTools,TrafficView,ADSBClient}.swift`.

- PaperKit `PaperMarkupViewController` wrapped for SwiftUI, with an author side table `[UUID: String]` stubbed with "You".
- `PlaneView`: `RealityView` builds the fuselage, wings and tail from `MeshResource.generateBox`/`generateCylinder`, with a seat marker.
- `BagMeasureView`: `ObjectCaptureSession.isSupported` → `ObjectCaptureView`; otherwise a message saying a LiDAR iPhone is required. Dimensions are checked against 55×40×20 cm by a Core function `cabinFit(_ dims: [Double]) -> [Double]` (overage per axis, with axes sorted); this function gets unit tests in Task 3's test file.
- `AskView`: `LanguageModelSession(tools: [GetTripTool, CheckItemTool])`.
- `ADSBClient.aircraft(near:radiusNM:)` calls `https://api.adsb.lol/v2/point/{lat}/{lon}/{nm}`, with an ODbL credit line.
- [ ] Build passes. Commit.

### Task 8: README, credits, publish

- [ ] README (why it beats MMT + WhatsApp, framework map, screenshots, honest limits), `CREDITS.md` (adsb.lol ODbL, OurAirports PD).
- [ ] Create the public `anupamchugh/trayce` repo and push.
- [ ] alcor-site: add a Trayce entry and page on a branch; deploy stays the owner's step.
