# Sourced by build scripts. Signs code with the local self-signed identity when it
# exists (stable across rebuilds, so Camera/Accessibility grants and Keychain access
# survive app updates), otherwise ad-hoc with an identifier-only designated
# requirement (weaker; macOS may still reset grants on update).

SIGNING_IDENTITY_NAME="FaceUnlock Local Signing"

signing_identity_available() {
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$SIGNING_IDENTITY_NAME\""
}

# sign_code PATH IDENTIFIER
sign_code() {
    local path="$1" identifier="$2"
    if signing_identity_available; then
        codesign --force --sign "$SIGNING_IDENTITY_NAME" --identifier "$identifier" --timestamp=none "$path"
    else
        codesign --force --sign - --identifier "$identifier" \
            -r="designated => identifier \"$identifier\"" "$path"
    fi
}

# sign_nested PATH: signs a bundled third-party binary (Sparkle's helpers) with the same
# identity, keeping its own identifier. Call inside-out, before signing the app.
sign_nested() {
    local path="$1"
    if signing_identity_available; then
        codesign --force --sign "$SIGNING_IDENTITY_NAME" --timestamp=none "$path"
    else
        codesign --force --sign - "$path"
    fi
}
