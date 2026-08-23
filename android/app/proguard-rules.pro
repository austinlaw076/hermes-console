# Flutter engine — reglas base incluidas por el plugin de Gradle, pero las
# repetimos explícitamente para builds personalizados.
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# flutter_secure_storage — usa JNI/reflection en Android Keystore.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# flutter_foreground_task — registra un servicio Android por nombre.
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# local_auth — usa BiometricPrompt por reflection.
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# flutter_tts — usa Android TTS por nombre.
-keep class com.tundralabs.fluttertts.** { *; }
-dontwarn com.tundralabs.fluttertts.**

# shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# qr_code_scanner_plus + ZXing (escaneo QR completamente open source).
# Conservamos el plugin, el visor embebido y los decodificadores en builds R8.
-keep class net.touchcapture.qr.flutterqrplus.** { *; }
-dontwarn net.touchcapture.qr.flutterqrplus.**
-keep class com.journeyapps.barcodescanner.** { *; }
-dontwarn com.journeyapps.barcodescanner.**
-keep class com.google.zxing.** { *; }
-dontwarn com.google.zxing.**

# Serialización Gson/JSON si aplica
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
