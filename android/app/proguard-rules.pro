# Extra R8 rules for release builds.
# Flutter's Gradle plugin adds this file to the release build automatically
# (it's read when android/app/proguard-rules.pro exists).

# Keep the no-argument constructor of Room databases (androidx.room.RoomDatabase).
# Room creates them by name at runtime, but R8 (code shrinking, full mode) removes the constructor
# when the library's own rules only keep the class. With google_mobile_ads, the older WorkManager
# it brings (work-runtime 2.7) then crashes the release build on launch:
#   Failed to create an instance of androidx.work.impl.WorkDatabase
# Added by Mobile IDE. Harmless if the app doesn't use Room.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
