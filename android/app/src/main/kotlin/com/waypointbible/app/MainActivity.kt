package com.waypointbible.app

import android.os.Bundle
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterFragmentActivity
import java.util.Calendar
import java.util.concurrent.TimeUnit

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        scheduleDailyVerseWorker()
    }

    private fun scheduleDailyVerseWorker() {
        val workManager = WorkManager.getInstance(this)

        // Immediate one-time run: seeds widget data on every app open so the
        // widget always reflects today's verse even after a fresh install.
        workManager.enqueueUniqueWork(
            "verse_widget_seed",
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<DailyVerseWorker>().build()
        )

        // Periodic run: fires once a day starting at the next midnight so the
        // widget rotates without the user having to open the app.
        val now = Calendar.getInstance()
        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 1)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val initialDelayMs = midnight.timeInMillis - now.timeInMillis

        workManager.enqueueUniquePeriodicWork(
            "verse_widget_daily",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<DailyVerseWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(initialDelayMs, TimeUnit.MILLISECONDS)
                .build()
        )
    }
}
