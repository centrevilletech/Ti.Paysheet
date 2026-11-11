# Ti.Paysheet: Titanium binds proxies and the module through JNI and reflection.
-keep class ti.paysheet.** { *; }
# Read by reflection for the stripeVersion property.
-keep class com.stripe.android.core.version.StripeSdkVersion { public static final java.lang.String VERSION_NAME; }
