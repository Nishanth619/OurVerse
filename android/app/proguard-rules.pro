# Flutter / Dart ProGuard rules for Closer

# Keep Flutter engine classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Keep home_widget plugin classes
-keep class es.antonborri.home_widget.** { *; }

# Keep Flutter local notifications plugin classes
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep Kotlin coroutines
-keepclassmembers class kotlinx.coroutines.** { *; }

# Keep model classes from being stripped (add yours here if needed)
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
