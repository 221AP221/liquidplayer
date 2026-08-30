# Windows-dasan — layihəni harada yoxlamaq olar

SwiftUI yalnız macOS-da, Xcode ilə qurulur. Windows-da build etmək mümkün deyil
(Swift kompilyatoru Windows-da var, amma UIKit/SwiftUI SDK-ları yoxdur).
Üç real yol var.

---

## 1. GitHub Actions — pulsuz, Mac lazım deyil ⭐ buradan başla

macOS runner-ləri **ictimai (public) repozitoriyalarda pulsuz və limitsizdir**.
Layihədə hazır `.github/workflows/ios.yml` var: hər push-da layihəni qurur,
simulyatorda işə salır və ekran görüntüsünü artefakt kimi yükləyir.

### Əvvəlcə workflow faylını yerinə qoy

Təhlükəsizlik səbəbindən `.github\workflows\` qovluğuna uzaqdan yaza bilmirəm,
ona görə fayl layihənin kökündə **`github-workflow-ios.yml`** adı ilə durur.
Onu bir dəfə köçür:

```powershell
cd $HOME\Desktop\LiquidPlayer
mkdir .github\workflows -Force
move github-workflow-ios.yml .github\workflows\ios.yml
```

Sonra:

```bash
cd Desktop/LiquidPlayer
git init
git add .
git commit -m "İlk skelet"
gh repo create liquidplayer --public --source=. --push
```

`gh` yoxdursa GitHub saytında boş **public** repo yarat, sonra:

```bash
git remote add origin https://github.com/İSTİFADƏÇİ/liquidplayer.git
git push -u origin main
```

Repoda **Actions** tabına keç. 5–10 dəqiqədən sonra:

- **build addımı yaşıldırsa** — kod kompilyasiya olunur.
- **qırmızıdırsa** — logu aç, `error:` sətirlərini mənə göndər, düzəldərəm.
- Aşağıda **simulator-screenshots** artefaktını yüklə — kitabxana ekranının
  şəklini görəcəksən.

Məhdudiyyət: bu, appı *işlətmək* deyil, yalnız qurmaq və bir kadr görməkdir.
Toxunub sınamaq üçün aşağıdakılar lazımdır.

> Repo private olarsa macOS dəqiqələri pulsuz deyil (dəqiqəsi ≈ $0.062,
> pulsuz planda 2 000 Linux-dəqiqəsi verilir, macOS ondan ~10× baha sayılır).
> Ona görə private saxlayacaqsansa 2-ci və ya 3-cü yola bax.

---

## 2. Bulud Mac saatlıq — appı əl ilə sınamaq üçün

Uzaqdan masaüstü ilə real macOS. Xcode qurursan, simulyatoru açırsan, toxunursan.

- **MacinCloud pay-as-you-go** — saatı $1-dan başlayır, minimum 25 saat
  öncədən ödəniş (≈$25). Mac mini M1/M2/M4, macOS Sequoia-ya qədər.
- Alternativlər: Scaleway Mac mini (saatlıq, amma minimum 24 saat),
  AWS EC2 Mac (minimum 24 saat, baha), XcodeClub, rentamac.io.

Bir günlük sessiyada layihəni qurub, simulyatorda tam sınaqdan keçirə bilərsən.

---

## 3. Öz Mac-ın — davamlı iş üçün yeganə normal yol

Bu layihəni həqiqətən inkişaf etdirəcəksənsə, uzun müddətdə ən ucuzu budur.
Mac mini (M4, baza konfiqurasiya) təxminən $599-dan başlayır; işlənmiş
MacBook Air M1 daha ucuz düşür. Xcode pulsuzdur.

**Real iPhone-da sınamaq:**
- Pulsuz Apple ID ilə — app 7 gün işləyir, sonra yenidən qurmaq lazımdır.
- Apple Developer Program ($99/il) — TestFlight, PiP və fon audio üçün
  bəzi entitlement-lər, App Store-a yerləşdirmə.

---

## Nə barədə xəbərdar olmalısan

**macOS-u Windows-da virtual maşında işlətmək** (VirtualBox/VMware) texniki
olaraq mümkündür, amma Apple-ın lisenziya şərtləri buna icazə vermir və
performans simulyator üçün praktiki deyil. Tövsiyə etmirəm.

**VLCKit CI-da.** Hazırkı workflow VLCKit olmadan qurur — kod `#if canImport`
ilə qorunub. CocoaPods əlavə edəndən sonra workflow-a `pod install` addımı
və `-workspace LiquidPlayer.xcworkspace` keçidi lazım olacaq.

---

## Ən sürətli yol, bir cümlə ilə

Reponu **public** olaraq GitHub-a at, Actions-un nəticəsini gözlə, çıxan
`error:` sətirlərini mənə göndər. Beləliklə bir qəpik xərcləmədən kodun
kompilyasiya olunduğuna əmin olacağıq; toxunaraq sınamaq isə bulud Mac və ya
öz Mac-ın işidir.
