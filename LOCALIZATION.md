# Localization Guide

FramePeek now supports localization (i18n) using SwiftUI's built-in localization system. The app will automatically use the user's system language preference.

## How It Works

1. **Automatic Localization**: All `Text()` views with string literals automatically localize when a `Localizable.xcstrings` file exists.

2. **Computed Strings**: For computed strings (like enum `displayName` properties), we use `String(localized:)` to ensure they're localized.

3. **System Language**: The app follows the user's macOS system language preference. Users can change their language in System Settings > Language & Region.

## Adding Translations

To add a new language:

1. Open `FramePeek/FramePeek/Localizable.xcstrings` in Xcode
2. Click the "+" button next to a string to add a new localization
3. Select the language you want to add (e.g., Spanish, French, German)
4. Enter the translated text
5. Repeat for all strings

Alternatively, you can manually edit the `.xcstrings` file by adding a new language code to each string's `localizations` object:

```json
"Settings" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Settings"
      }
    },
    "es" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Configuración"
      }
    }
  }
}
```

## Adding New Strings

When adding new user-facing strings to the app:

1. **For Text() views**: Just use the string literal - it will automatically be added to the localization file when Xcode extracts strings.

2. **For computed strings**: Use `String(localized: "Your String")` to ensure it's localized.

3. **For string interpolation**: Use format strings:
   ```swift
   Text(String(format: String(localized: "Version %@"), version))
   ```

## Supported Languages

Currently, the app includes English (en) as the base language. To add more languages:

1. Add the language in Xcode's project settings (Project > Info > Localizations)
2. Add translations to `Localizable.xcstrings` for each string
3. The app will automatically use the appropriate language based on the user's system preference

## Testing Localizations

To test different languages:

1. Change your Mac's language in System Settings > Language & Region
2. Restart the app to see the new language
3. Or use Xcode's scheme editor to set a different language for debugging


