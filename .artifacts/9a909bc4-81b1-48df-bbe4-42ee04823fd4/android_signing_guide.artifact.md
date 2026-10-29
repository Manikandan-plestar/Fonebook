# Android App Signing Guide

Google Play **requires** a signed bundle using a production keystore. The "normal" bundle created with the default settings uses a debug key, which Google Play will reject.

Follow these steps to sign your app correctly.

## Step 1: Create a Keystore
Run this command in your terminal to generate a keystore file.

> [!CAUTION]
> **IMPORTANT**: Keep this file safe! If you lose it, you will never be able to update your app on the Play Store again.

```bash
keytool -genkey -v -keystore fonebook-release.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
- When asked, enter a strong password and remember it.
- This will create a file named `fonebook-release.keystore` in your current directory. **Move it to the `android/app/` folder.**

## Step 2: Create `key.properties`
Create a file named `key.properties` in the `android/` directory with the following content:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=fonebook-release.keystore
```
*(Replace `YOUR_STORE_PASSWORD` and `YOUR_KEY_PASSWORD` with the passwords you created in Step 1.)*

## Step 3: Update `build.gradle.kts`
I will update your [build.gradle.kts](file:///C:/Users/Plestar/StudioProjects/FoneBook/android/app/build.gradle.kts) to use this signing configuration.

```kotlin
// I will apply this change now...
```

## Step 4: Build the Signed Bundle
Once configured, run:
```bash
flutter build appbundle
```
The resulting file at `build/app/outputs/bundle/release/app-release.aab` will now be **Signed** and ready for Google Play.
