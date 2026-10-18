# Geonix Music Player — Flutter app

The desktop UI. See the main [README](../README.md) for setup and how it talks to the Rust backend.

```bash
flutter run -d linux                       # backend on 127.0.0.1:7878
flutter run -d linux --dart-define=GEONIX_API=http://127.0.0.1:7979
flutter analyze && flutter test
```
