# Captain Flutter setup

```bash
cd apps/captain
flutter create . --project-name synaptic_go_captain
flutter pub get
flutter run
```

Production API: غيّر `defaultBaseUrl` في `lib/services/app_state.dart` إلى:

```dart
return 'https://api.synapticstudio.tech';
```
