package com.tntlikely.beecount

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Never starts Flutter, logs notification text, or sends content over the network. */
class BillingNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        BillingNotificationStore.connected = true
        BillingNotificationStore.connectionTime = System.currentTimeMillis()
        // Recover still-visible notifications after OS reconnect, using the original post time.
        try { activeNotifications?.forEach { capture(it) } } catch (_: SecurityException) { }
    }
    override fun onListenerDisconnected() {
        BillingNotificationStore.connected = false
        if (Build.VERSION.SDK_INT >= 24) requestRebind(ComponentName(this, javaClass))
    }
    override fun onNotificationPosted(sbn: StatusBarNotification) { capture(sbn) }
    private fun capture(sbn: StatusBarNotification) {
        try {
            val n = sbn.notification
            if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
            val e = n.extras
            val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val body = e.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                ?.takeIf { it.isNotBlank() } ?: e.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
            BillingNotificationStore.capture(this, sbn.packageName, sbn.key, sbn.postTime, title, body)
        } catch (_: Exception) { BillingNotificationStore.lastError = "通知保存失败，请检查设备存储空间" }
    }
}

object BillingNotificationStore {
    @Volatile var connected = false
    @Volatile var connectionTime = 0L
    @Volatile var lastError = ""
    private val defaults = listOf("com.tencent.mm", "com.eg.android.AlipayGphone", "com.icbc", "com.chinamworld.main", "com.chinamworld.bocmbci", "com.android.bankabc", "cmb.pb", "com.bankcomm.Bankcomm", "com.psbc.mbank", "com.pingan.paces.ccms", "com.cib.cibmb", "com.spdb.pccc.awap", "com.cebbank.mobile.cemb")
    private fun file(c: Context) = AtomicFile(File(c.noBackupFilesDir, "billing_notifications.json"))
    @Synchronized private fun read(c: Context): JSONObject {
        val f = file(c)
        if (!f.baseFile.exists()) return JSONObject().put("enabled", false).put("packages", JSONArray(defaults)).put("events", JSONArray())
        return JSONObject(String(f.readFully(), Charsets.UTF_8))
    }
    @Synchronized private fun write(c: Context, data: JSONObject) {
        val f = file(c)
        val out = f.startWrite()
        try { out.write(data.toString().toByteArray(Charsets.UTF_8)); f.finishWrite(out) }
        catch (e: Exception) { f.failWrite(out); throw e }
    }
    @Synchronized fun capture(c: Context, pkg: String, key: String, time: Long, title: String, body: String) {
        val data = read(c)
        if (!data.optBoolean("enabled")) return
        val packages = data.getJSONArray("packages")
        if ((0 until packages.length()).none { packages.getString(it) == pkg }) return
        val text = "$title\n$body".take(8000)
        // Ignore conversations and unrelated notifications, even from allowed apps.
        if (!Regex("支付|付款|消费|支出|扣款|交易|转账|收款|到账|退款|余额|人民币|[¥￥]").containsMatchIn(text)) return
        val id = MessageDigest.getInstance("SHA-256").digest("$pkg|$key|$time|$text".toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        val events = data.getJSONArray("events")
        if ((0 until events.length()).any {
            val e = events.getJSONObject(it)
            e.getString("id") == id || (e.optString("package") == pkg &&
                e.optString("text") == text && kotlin.math.abs(e.optLong("postedAt") - time) < 10000)
        }) return
        // Resolved entries retain only fingerprints; pending raw text is never silently evicted.
        if (events.length() >= 5000) { lastError = "本地采集队列已满，请处理待确认并清理历史；期间请用账单导入补漏"; return }
        events.put(JSONObject().put("id", id).put("package", pkg).put("postedAt", time)
            .put("capturedAt", System.currentTimeMillis()).put("title", title.take(1000)).put("text", text).put("state", "pending"))
        data.put("lastCapturedAt", System.currentTimeMillis())
        write(c, data)
    }
    fun setup(c: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "beecount/notification_capture").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> {
                        val d = read(c)
                        val granted = Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners")
                            ?.split(':')?.any { ComponentName.unflattenFromString(it) == ComponentName(c, BillingNotificationListener::class.java) } == true
                        val a = d.getJSONArray("events")
                        result.success(mapOf("enabled" to d.optBoolean("enabled"), "granted" to granted, "connected" to connected,
                            "connectedAt" to connectionTime, "lastCapturedAt" to d.optLong("lastCapturedAt"),
                            "error" to if (a.length() >= 5000) "本地采集队列已满，请清理并使用账单导入补漏" else lastError,
                            "packages" to (0 until d.getJSONArray("packages").length()).map { d.getJSONArray("packages").getString(it) },
                            "pending" to (0 until a.length()).count { a.getJSONObject(it).getString("state") == "pending" }))
                    }
                    "configure" -> synchronized(this) {
                        val d = read(c)
                        call.argument<Boolean>("enabled")?.let { d.put("enabled", it) }
                        call.argument<List<String>>("packages")?.let { p ->
                            require(p.size <= 50 && p.all { it.matches(Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)+")) })
                            d.put("packages", JSONArray(p))
                        }
                        write(c, d); result.success(null)
                    }
                    "openAccess" -> { c.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null) }
                    "reconnect" -> { if (Build.VERSION.SDK_INT >= 24) NotificationListenerService.requestRebind(ComponentName(c, BillingNotificationListener::class.java)); result.success(null) }
                    "events" -> result.success(read(c).getJSONArray("events").toString())
                    "resolve" -> synchronized(this) {
                        val d = read(c); val a = d.getJSONArray("events")
                        val id = call.argument<String>("id"); val state = call.argument<String>("state")
                        require(state == "confirmed" || state == "ignored")
                        for (i in 0 until a.length()) {
                            val e = a.getJSONObject(i)
                            if (e.getString("id") == id) {
                                e.put("state", state); e.remove("title"); e.remove("text")
                                e.put("resolvedAt", System.currentTimeMillis())
                            }
                        }
                        write(c, d); result.success(null)
                    }
                    "clear" -> synchronized(this) { val d = read(c); d.put("events", JSONArray()); write(c, d); lastError = ""; result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("CAPTURE_ERROR", "无法读写本地采集数据或打开系统设置，请检查存储空间及系统限制", null) }
        }
    }
}
