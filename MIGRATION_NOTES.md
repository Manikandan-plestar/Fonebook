# Fone Book Flutter Migration

Package and bundle id: `com.plestar.fonebook`

Version: `1.0.0+36`

The native Java package was `com.plestar.tpdirectory`. This Flutter project uses `com.plestar.fonebook` for Android and iOS.

## Ported App Flows

- Main directory search, country/place scope, contact results, details, favourite, call, landline, WhatsApp, email, and Skype actions.
- Near Me and Worldwide directory views.
- Contact create, server preload, update, deletion, image upload, categories, address, state/city/country, keywords, additional skills/services, landline, WhatsApp, Skype, and publishing.
- Additional named phone numbers using the native `name:number` server format.
- Keyword editing with the native Individual five-keyword limit and premium restriction.
- Profile settings for publish, verified/all access, and the native `show_contact` field code.
- Mobile/email verification request and update flows.
- Verification purchase products:
  - `individual_verification`
  - `organization_verification`
- Promotion matching, targeting, balance, priority, and products:
  - `promote_1`
  - `promote_2`
  - `promote_3`
  - `promote_4`
- Organic and paid traffic reports with the original report endpoints.
- Premium status, reports, session storage, permissions, and logout.
- Original Android logo and launcher artwork, plus generated matching iOS icons.
- Native API and image base URLs.

## External Configuration Required

The app-side conversion is present, but these external services cannot be embedded or completed from Java source alone:

- Google Play Console and App Store Connect must contain the listed in-app purchase product identifiers.
- iOS signing, provisioning, and App Store capabilities must be configured on macOS/Xcode.
- The existing backend endpoints must remain available and return the same JSON fields.
- The old Java app sent some OTP messages directly through AWS Pinpoint/SNS. The Flutter app uses the existing verification backend endpoints so credentials are not shipped in both Android and iOS clients.

## Verification

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

All three commands pass on the converted project.
