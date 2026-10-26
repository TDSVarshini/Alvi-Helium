# The vendor SDK builds response beans reflectively and ships no keep rules.
-keep class com.oudmon.** { *; }
-keep class com.realsil.** { *; }
-keep class com.jieli.** { *; }
-dontwarn com.androidnetworking.**
-dontwarn com.oudmon.**
