package dev.locus.activity

import android.app.PendingIntent
import android.content.Context
import android.os.Build
import dev.locus.core.ConfigManager

internal class ActivityPendingIntentChecks(private val context: Context) {
    fun checks(): List<Pair<String, () -> Unit>> = listOf(
        "testActivityRecognitionPendingIntentIsMutable" to ::verifyMutablePendingIntent,
    )

    private fun verifyMutablePendingIntent() {
        check(context.packageName == "dev.locus.test") { "Native checks require the isolated library test package" }
        val manager = MotionManager(context, ConfigManager(context))
        val method = MotionManager::class.java.getDeclaredMethod("createActivityPendingIntent")
        method.isAccessible = true
        val pendingIntent = method.invoke(manager) as? PendingIntent
            ?: throw AssertionError("MotionManager must create a PendingIntent")
        try {
            if (pendingIntent.creatorPackage != context.packageName) {
                throw AssertionError("Expected the test package to own the PendingIntent")
            }
            // Play services attaches the activity result as extras on delivery.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && pendingIntent.isImmutable) {
                throw AssertionError("Activity recognition PendingIntent must be mutable on Android 12+")
            }
        } finally {
            pendingIntent.cancel()
        }
    }
}
