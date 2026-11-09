# App localization

Hey Mac uses macOS's preferred language list. The release script copies each
`packaging/<language>.lproj` directory into the app's main resource bundle, so
SwiftUI controls and system permission prompts use the selected language without
an in-app language switch.

## Add a translation

1. Create `packaging/<language>.lproj/Localizable.strings` (for example,
   `packaging/ru.lproj/Localizable.strings`).
2. For a literal used by SwiftUI, use the exact English text in the source as
   the key and put the translated text on the right:

   ```text
   "Check for Updates…" = "…";
   ```

   The English source catalog in `packaging/en.lproj/Localizable.strings`
   contains the app's current source keys, including runtime format strings.

3. Keep format placeholders such as `%@`, `%d`, `%ld`, and `%lld` in the translated
   value, in the right order. Keep product names such as Hey Mac and Touch ID as
   product names unless a translation convention calls for otherwise.
4. Add `InfoPlist.strings` in the same locale for macOS permission explanations.
   Do not change the English `NSCameraUsageDescription` without updating the
   matching localized source value.
5. For a phrase assembled or passed around as a runtime `String`, look it up
   with `L10n.text(_:comment:)`. For a phrase with values, use
   `L10n.format(_:_:comment:)` and keep each placeholder in the same position.
6. Translate the count rules in `Localizable.stringsdict` as well as the
   ordinary strings file. Russian needs the appropriate one, few, many, and
   other forms. Do not concatenate a number with singular or plural nouns.

The English source locale is `en`. English is also the fallback language when
a translation omits a key. Keep translation changes in the relevant `.lproj`
folder so they can be reviewed independently.
