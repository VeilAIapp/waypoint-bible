package com.waypointbible.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class WaypointWidgetSmallProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId, widgetData)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        widgetData: SharedPreferences
    ) {
        val verseText = widgetData.getString(
            "verse_text",
            "The steadfast love of the Lord never ceases; his mercies never come to an end."
        ) ?: ""
        val verseRef = widgetData.getString("verse_ref", "Lamentations 3:22-23") ?: ""

        val views = RemoteViews(context.packageName, R.layout.widget_small)
        views.setTextViewText(R.id.verse_text, "“$verseText”")
        views.setTextViewText(R.id.verse_ref, verseRef)

        // Tap anywhere to open the app.
        val openPendingIntent = openAppIntent(context, widgetId)
        views.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)

        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun openAppIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
