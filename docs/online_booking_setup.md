# Mebs Kurum Takip - Online Randevu Modülü

Bu doküman aynı Flutter projesinde **iki ayrı web entrypoint** ile online randevu modülünü kurmak için hazırlanmıştır.

## 1) Önerilen Klasör Yapısı

```text
lib/
  core/
    app_bootstrap.dart
    theme/
      booking_theme.dart
    utils/
      date_time_utils.dart
  models/
    booking_models.dart
    booking_settings.dart
    customer_profile.dart
    org_public_profile.dart
    org_service.dart
  services/
    booking_api_service.dart
    customer_service.dart
    org_public_service.dart
    phone_verification_service.dart
  admin/
    admin_app.dart
  booking/
    booking_app.dart
    controllers/
      booking_flow_controller.dart
    pages/
      booking_home_page.dart
      org_booking_page.dart
    widgets/
      booking_status_views.dart
  main.dart
  main_admin.dart
  main_booking.dart
```

## 2) Firestore Veri Modeli

### `orgs/{orgId}`
- `name`
- `slug`
- `district`
- `phone`
- `address`
- `logoUrl`
- `bookingEnabled`
- `bookingSettings`:
  - `enabled`
  - `maxDaysAhead`
  - `minHoursBefore`
  - `slotMinutes`
  - `allowSameDay`
  - `weekendOpen`
  - `publicInfoText`
  - `successText`
- `workingHours`:
  - `1..7` gün map’i (`isOpen`, `windows[{start,end}]`)
  - `closedDates: [yyyy-MM-dd]`
- `createdAt`
- `updatedAt`

### `orgSlugs/{slug}` (önerilen, hızlı lookup)
- `orgId`
- `active`
- `createdAt`

Not: `orgSlugs` ile slug çözümü O(1) doküman okuma olur. Fallback olarak `orgs.slug` query de açık tutuldu.

### `orgs/{orgId}/services/{serviceId}`
- `orgId`
- `name`
- `durationMinutes`
- `price` (opsiyonel)
- `active`
- `category` (opsiyonel)
- `description` (opsiyonel)

### `customers/{customerId}`
- `orgId`
- `fullName`
- `phone` (normalize)
- `birthDate`
- `address`
- `createdAt`
- `updatedAt`

### `bookings/{bookingId}`
- `orgId`
- `customerId`
- `customerName`
- `customerPhone`
- `serviceId`
- `serviceName`
- `bookingDate`
- `startTime`
- `endTime`
- `status` (`pending`, `confirmed`, `cancelled`)
- `source` (`online`)
- `notes`
- `staffId` (opsiyonel)
- `staffName` (opsiyonel)
- `createdAt`

### `bookingLocks/{lockId}`
- Slot çakışma kilidi için transaction sırasında yazılır.
- `orgId`, `staffId`, `lockStart`, `lockEnd`, `bookingId`, `createdAt`, `expiresAt`

## 3) Gerekli Model Sınıfları

Eklenen dosyalar:
- `lib/models/booking_settings.dart`
- `lib/models/org_public_profile.dart`
- `lib/models/org_service.dart`
- `lib/models/customer_profile.dart`
- `lib/models/booking_models.dart`

Bu modeller booking ayarları, çalışma saatleri, müşteri, hizmet, müsait slot ve rezervasyon payload’larını kapsar.

## 4) Gerekli Servis Sınıfları

Eklenen servisler:
- `lib/services/org_public_service.dart`
  - Slug -> kurum çözümü (`orgSlugs` + fallback `orgs.slug`)
  - aktif hizmet listeleme
- `lib/services/customer_service.dart`
  - telefon normalize
  - kurum bazlı müşteri bul/upsert
- `lib/services/phone_verification_service.dart`
  - OTP soyutlama arayüzü
  - `BypassPhoneVerificationService` (OTP’siz)
- `lib/services/booking_api_service.dart`
  - backend endpoint ile availability ve create
  - API yoksa sınırlı local fallback availability

## 5) Routing Yapısı

Booking app route çözümü:
- `/` -> `BookingHomePage`
- `/:slug` -> `OrgBookingPage`

`OrgBookingPage`, `slug` parametresiyle Firestore’dan kurum çözümleyip booking akışını başlatır.

## 6) Booking Web Başlangıç İskeleti

Ana booking uygulaması:
- `lib/booking/booking_app.dart`
- `lib/booking/pages/org_booking_page.dart`
- `lib/booking/controllers/booking_flow_controller.dart`

Akış adımları:
1. Telefon doğrulama (OTP veya bypass)
2. Yeni müşteri formu / kayıtlı müşteri auto geçiş
3. Hizmet seçimi
4. Tarih-saat seçimi
5. Son onay
6. Başarı ekranı

Ek durum ekranları:
- Kurum bulunamadı
- Online randevu kapalı
- Loading / error

## 7) `main_booking.dart`

Eklenen giriş noktası:
- Firebase bootstrap
- locale date init
- booking app run

```bash
flutter run -d chrome -t lib/main_booking.dart
```

## 8) Slug Çözümleme Mantığı

`OrgPublicService.findBySlug` sırası:
1. `orgSlugs/{slug}` dokümanı oku (hızlı yol)
2. Varsa `orgId` ile `orgs/{orgId}` oku
3. Yoksa fallback: `orgs.where(slug==...)`

Bu sayede yeni kurum açıldığında sadece Firestore kaydı yeterli olur; deploy gerekmez.

## 9) Müşteri Kontrol Akışı

`BookingFlowController`:
1. Telefon alınır
2. OTP doğrulama veya bypass
3. `customers` içinde `orgId + phone` aranır
4. Bulunursa hizmet seçimine geçilir
5. Bulunmazsa müşteri formu açılır ve upsert yapılır

## 10) Hizmet Seçimi Ekranı

`_ServiceStep` (`org_booking_page.dart`):
- Aktif hizmetler listelenir
- Süre (`durationMinutes`) gösterilir
- Seçimden sonra tarih-saat adımına geçiş

## 11) Tarih ve Saat Seçimi Ekranı

`_DateTimeStep`:
- tarih picker
- `booking_api_service.fetchAvailability`
- uygun slotlar `ChoiceChip` ile listelenir
- seçim sonrası onay ekranı

## 12) Rezervasyon Oluşturma Mantığı

Frontend:
- `BookingDraft` hazırlanır
- backend `/booking/create` endpointine gönderilir

Backend (`index.js`):
- org ve ayarlar doğrulanır
- min/max zaman kuralı kontrol edilir
- transaction içinde overlap + lock kontrolü yapılır
- booking + lock belgeleri atomik yazılır

## 13) Double Booking Önleme

Uygulanan yöntem:
1. **Transaction** içinde aynı gün çakışan booking query
2. Slot bazlı `bookingLocks` dokümanları deterministik id ile oluşturma
3. Var olan lock veya overlap varsa işlem `409 slot_not_available` döner

Bu yöntem yarış durumlarına karşı güvenlidir.

## 14) Firebase Hosting Notları

`firebase.json` çoklu hosting target yapısına geçirildi:
- `admin` -> `build/web_admin`
- `booking` -> `build/web_booking`
- Her ikisinde `"**" -> "/index.html"` rewrite var (SPA refresh 404 çözümü)

`.firebaserc` içine target örnekleri eklendi:
- `admin`: `kurumtakip-admin`
- `booking`: `randevu-mebs`

> Not: Site id’lerini Firebase Hosting’deki gerçek isimlerle güncelleyin.

Örnek build/deploy:

```bash
flutter build web -t lib/main_admin.dart --release --output build/web_admin
flutter build web -t lib/main_booking.dart --release --output build/web_booking

firebase deploy --only hosting:admin
firebase deploy --only hosting:booking
```

Örnek domain eşleşmesi:
- `admin` target -> mevcut yönetim domaini
- `booking` target -> `randevu.mebs.com.tr`

## 15) Cloud Function / Backend Örneği

Bu repo Cloud Run tarzı `index.js` kullanıyor. Booking için iki endpoint eklendi:
- `POST /booking/availability`
- `POST /booking/create`

Aynı mantık Firebase Functions’a da taşınabilir; transaction mantığı aynıdır.

## 16) Firestore Security Rules Taslağı

Yeni `firestore.rules` dosyası eklendi:
- public read: `orgSlugs`, booking açık `orgs` ve aktif `services`
- `customers`: sadece staff
- `bookings`: client direct write kapalı
- `bookingLocks`: tamamen backend kontrolünde

Önemli: Bu taslak `request.auth.token.staff` claim’i varsayar. Mevcut kimlik modelinize göre helper fonksiyonları güncelleyin.

---

## Yönetim Paneli Entegrasyonu İçin Kısa Yol Haritası

Admin panelde kuruma şu alanları ekleyin:
- `slug` alanı (unique)
- `bookingEnabled` toggle
- `bookingSettings` formu
- `workingHours` editörü
- `services` yönetimi
- gösterilecek link:
  - `https://randevu.mebs.com.tr/{slug}`
- kopyala butonu
- online bookings liste ekranı (`bookings.where(orgId==selectedOrg)`)

Bu yapı ile yeni kurum eklendiğinde yalnızca Firestore kaydı yeterlidir; ek deploy gerekmez.
