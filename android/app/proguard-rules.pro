# Keep TFLite native bindings
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep TFLite GPU delegate
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# Keep Flutter sound recorder
-keep class com.dooboolab.** { *; }
-dontwarn com.dooboolab.**
