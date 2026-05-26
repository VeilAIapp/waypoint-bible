package com.waypointbible.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class DailyVerseWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val verse = getDailyVerse()

        // Write to the same SharedPreferences file home_widget reads from
        applicationContext
            .getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("verse_text", verse.text)
            .putString("verse_ref", verse.ref)
            .apply()

        // Broadcast update to each widget provider
        val manager = AppWidgetManager.getInstance(applicationContext)
        listOf(WaypointWidgetMediumProvider::class.java).forEach { providerClass ->
            val ids = manager.getAppWidgetIds(ComponentName(applicationContext, providerClass))
            if (ids.isNotEmpty()) {
                applicationContext.sendBroadcast(
                    Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                        component = ComponentName(applicationContext, providerClass)
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                )
            }
        }

        return Result.success()
    }
}
