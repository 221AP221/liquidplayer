# LiquidPlayer — iOS 18 universal media player

SwiftUI + SwiftData skeleti. Lokal audio və video fayllar; oxutma AVFoundation
və VLCKit arasında avtomatik bölünür.

## Layihəni açmaq

Bu qovluqda `.xcodeproj` yoxdur — layihə [XcodeGen](https://github.com/yonaskolb/XcodeGen)
manifestindən qurulur, beləliklə fayl əlavə edəndə merge konflikti olmur.

```bash
brew install xcodegen
cd LiquidPlayer
xcodegen generate
open LiquidPlayer.xcodeproj
```

XcodeGen istəmirsənsə: Xcode-da yeni iOS App layihəsi yarat (SwiftUI, iOS 18),
sonra `Sources/` qovluğunu olduğu kimi sürüşdür və `Sources/App/Info.plist`-i
target-ın Info.plist-i kimi göstər.

## VLCKit əlavə etmək

Kod VLCKit **olmadan da kompilyasiya olunur** — `VLCPlaybackEngine.swift` bütünlüklə
`#if canImport(MobileVLCKit)` içindədir. Onsuz MKV/FLAC faylları
«format açılmır» xəbərdarlığı verir, qalan hər şey işləyir.

Ən etibarlı yol CocoaPods-dur:

```ruby
# Podfile
platform :ios, '18.0'
target 'LiquidPlayer' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'
end
```

```bash
pod install
open LiquidPlayer.xcworkspace
```

VLCKit-in rəsmi Swift Package dəstəyi qeyri-sabitdir; SPM istifadə edəcəksənsə
əvvəlcə seçdiyin repozitoriyanın hazırkı vəziyyətini yoxla.

## Qatlar

| Qovluq | Nə edir |
|---|---|
| `DesignSystem/` | Rəng, ölçü, tipoqrafiya tokenləri; şüşə səth və ortaq komponentlər |
| `Models/` | SwiftData modelləri (`MediaItem`, `LibraryFolder`) və oxutma tipləri |
| `Library/` | Qovluq idxalı, metadata oxunması, sorğular |
| `Player/` | `PlaybackEngine` protokolu, AVFoundation və VLC tətbiqləri, `PlayerController` |
| `Screens/` | SwiftUI ekranları |
| `Localization/` | `Localizable.xcstrings` — AZ (mənbə) + EN |

## Əsas qərarlar

**Mühərrik marşrutlaşdırması.** `EngineRouter` faylın uzantısına baxıb qərar verir:
AVFoundation-ın etibarlı oxuduğu formatlar ora gedir (aparat dekoderi, PiP, AirPlay video),
qalanı VLC-yə. Ekranlar hansı mühərriyin işlədiyini bilmir — yalnız `PlaybackSnapshot` görür.
Mühərrik dəyişəndə yeganə dəyişən yer `EngineRouter`-dir.

**VLC-nin qiyməti UI-da görünür.** VLC işə düşəndə `PlayerController` bir dəfə
xəbərdarlıq göstərir: PiP yoxdur, AirPlay yalnız güzgü, batareya iki dəfə sürətli boşalır.
İstifadəçi «gizlət» seçə bilər.

**Fayllar köçürülmür.** Yalnız security-scoped bookmark saxlanılır. Bookmark köhnəlibsə
avtomatik yenilənir; həll olunmursa element `isMissing` işarələnir və kitabxanada gizlənir —
amma oxunmuş yeri, əlfəcinləri silinmir, qovluq qayıdanda hər şey yerinə düşür.

**Treklər hər iki mühərrikdə eyni görünür.** `MediaTrack` sadə struktdur;
AVFoundation-da `AVMediaSelectionOption` indeksinə, VLC-də isə tam indeksə çevrilir.
Siyahı gec gəldiyi üçün mühərrik `onTracksChanged` çağırır və `PlayerController` onu
saxlanan dəyərə köçürür — `@Observable` yalnız belə yenilənməni işə salır.

**PiP yalnız AVFoundation-da.** `AVPictureInPictureController` player layer-ə bağlanır və
`canStartPictureInPictureAutomaticallyFromInline` sayəsində istifadəçi appdan çıxanda
video özü kiçik pəncərəyə keçir. VLC ilə oynayan fayllarda düymə əvəzinə AirPlay görünür,
trek vərəqəsində isə nəyin itdiyi açıq yazılır.

**Metadata oxunması MainActor-dan kənardadır.** `AVAsset`, `AVMetadataItem` və
`AVAssetTrack` Sendable deyil, ona görə onlar `probeMetadata` funksiyasından bayıra
çıxmır — yalnız Sendable `Probe` strukturu qayıdır. Swift 6 xəbərdarlıqları bununla bağlı idi.

**Tərəqqi tez-tez yazılmır.** `PlayerController` hər ~2 saniyədə bir SwiftData-ya yazır,
trek dəyişəndə isə məcburi. Böyük kitabxanada bu fərq hiss olunur.

## Nə hazır deyil

- Səsli kitab fəsilləri, əlfəcinlər
- Ekvalayzer (`AVAudioEngine` və ya VLC-nin öz EQ-su)
- iPad sidebar layoutu
- Kitabxananın fon yenilənməsi (qovluğa yeni fayl düşəndə)

## Bilinən texniki qeydlər

- **Swift 5 dil rejimi.** `project.yml`-də `SWIFT_VERSION: 5.0`, `SWIFT_STRICT_CONCURRENCY: targeted`.
  Səbəb: `MPRemoteCommandCenter` closure-ları Sendable işarələnməyib və Swift 6 rejimində
  `PlayerController`-i tutmaq xəta verir. Swift 6-ya keçid ayrıca addımdır — remote komandaları
  nazik `nonisolated` adapterə bağlamaq kifayət edir.
- **Axtarış yaddaşdadır.** SwiftData predikatları `localizedStandardContains` dəstəkləmir.
  10 000 fayldan sonra FTS5 indeksi lazım olacaq.
- **AVFoundation MKV oxumur**, ona görə idxal zamanı belə faylların metadatası boş qalır —
  başlıq fayl adından götürülür, dəqiq uzunluq isə fayl ilk dəfə VLC ilə açılanda yazılır.
