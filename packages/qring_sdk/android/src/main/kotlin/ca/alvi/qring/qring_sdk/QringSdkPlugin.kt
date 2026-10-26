package ca.alvi.qring.qring_sdk

import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.oudmon.ble.base.bean.SleepDisplay
import com.oudmon.ble.base.bluetooth.BleAction
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.bluetooth.DeviceManager
import com.oudmon.ble.base.bluetooth.QCBluetoothCallbackCloneReceiver
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.DfuHandle
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.LargeDataHandler
import com.oudmon.ble.base.communication.bigData.AlarmNewEntity
import com.oudmon.ble.base.communication.bigData.BloodOxygenEntity
import com.oudmon.ble.base.communication.bigData.IReadAlarmCallback
import com.oudmon.ble.base.communication.entity.StartEndTimeEntity
import com.oudmon.ble.base.communication.req.DndReq
import com.oudmon.ble.base.communication.req.SetSitLongReq
import com.oudmon.ble.base.communication.bigData.bean.IntervalTemperatureEntity
import com.oudmon.ble.base.communication.entity.BlePressure
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.req.BaseReqCmd
import com.oudmon.ble.base.communication.req.BloodOxygenSettingReq
import com.oudmon.ble.base.communication.req.DeviceSupportReq
import com.oudmon.ble.base.communication.req.FindDeviceReq
import com.oudmon.ble.base.communication.req.HeartRateSettingReq
import com.oudmon.ble.base.communication.req.HrvSettingReq
import com.oudmon.ble.base.communication.req.NotificationEventNotifyReq
import com.oudmon.ble.base.communication.req.PhoneSportReq
import com.oudmon.ble.base.communication.req.PressureSettingReq
import com.oudmon.ble.base.communication.req.RealTimeHeartRate
import com.oudmon.ble.base.communication.req.RestoreKeyReq
import com.oudmon.ble.base.communication.req.SetTimeReq
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.oudmon.ble.base.communication.req.SugarLipidsSettingReq
import com.oudmon.ble.base.communication.req.TargetSettingReq
import com.oudmon.ble.base.communication.req.TimeFormatReq
import com.oudmon.ble.base.communication.req.TouchControlReq
import com.oudmon.ble.base.communication.responseImpl.DeviceNotifyListener
import com.oudmon.ble.base.communication.responseImpl.DeviceSportNotifyListener
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import com.oudmon.ble.base.communication.rsp.BatteryRsp
import com.oudmon.ble.base.communication.rsp.DeviceNotifyRsp
import com.oudmon.ble.base.communication.rsp.DeviceSupportFunctionRsp
import com.oudmon.ble.base.communication.rsp.HRVRsp
import com.oudmon.ble.base.communication.rsp.PressureRsp
import com.oudmon.ble.base.communication.rsp.ReadHeartRateRsp
import com.oudmon.ble.base.communication.rsp.RealTimeHeartRateRsp
import com.oudmon.ble.base.communication.rsp.SetTimeRsp
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.communication.rsp.TodaySportDataRsp
import com.oudmon.ble.base.communication.sport.SportPlusEntity
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import com.oudmon.ble.base.scan.ScanWrapperCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges the QC Wireless ring SDK to Flutter.
 *
 * The SDK calls back on its own HandlerThread, so every reply and event is
 * posted to the main looper before it reaches Flutter. The SDK has no
 * command timeouts, so each call here arms its own.
 */
class QringSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  private lateinit var context: Context
  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    initSdk(context.applicationContext as Application)
    methods = MethodChannel(binding.binaryMessenger, "qring_sdk/methods").also { it.setMethodCallHandler(this) }
    events = EventChannel(binding.binaryMessenger, "qring_sdk/events").also { it.setStreamHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    events.setStreamHandler(null)
  }

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
    eventSink = sink
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val reply = Reply(result)
    try {
      when (call.method) {
        "startScan" -> startScan(call.argument<Int>("timeoutMs") ?: 15_000, reply)
        "stopScan" -> { stopScan(); reply.ok(null) }
        "connect" -> connect(call.argument<String>("id")!!, reply)
        "disconnect" -> disconnect(unbind = false, reply)
        "unbind" -> disconnect(unbind = true, reply)
        "isConnected" -> reply.ok(BleOperateManager.getInstance().isConnected)
        "syncTime" -> syncTime(reply)
        "getBattery" -> getBattery(reply)
        "getVersions" -> getVersions(reply)
        "setUserProfile" -> setUserProfile(call, reply)
        "setGoals" -> setGoals(call, reply)
        "findDevice" -> fire(FindDeviceReq(), reply)
        "vibrate" -> vibrate(call, reply)
        "setTouchEvents" -> setTouchEvents(call.argument<Boolean>("enabled") ?: true, reply)
        "setAutoMeasure" -> setAutoMeasure(call, reply)
        "setAlarm" -> setAlarm(call, reply)
        "getAlarms" -> getAlarms(reply)
        "setDoNotDisturb" -> fire(DndReq.getWriteInstance(call.argument<Boolean>("enabled") ?: false,
          window(call.argument<Int>("start") ?: 0, call.argument<Int>("end") ?: 0)), reply)
        "setSedentaryReminder" -> setSedentary(call, reply)
        "factoryReset" -> fire(RestoreKeyReq(Constants.CMD_RE_STORE), reply)
        "startOta" -> startOta(call.argument<String>("path")!!, reply)
        "getActivitySummary" -> getActivitySummary(day(call), reply)
        "getActivityDetail" -> getActivityDetail(day(call), reply)
        "getHeartRate" -> getHeartRate(day(call), reply)
        "getSpO2" -> getSpO2(day(call), reply)
        "getHrv" -> getHrv(day(call), reply)
        "getStress" -> getStress(day(call), reply)
        "getTemperature" -> getTemperature(day(call), reply)
        "getBloodPressure" -> getBloodPressure(day(call), reply)
        "getSleep" -> getSleep(day(call), reply)
        "getWorkouts" -> getWorkouts(day(call), reply)
        "measure" -> measure(call.argument<String>("type")!!, call.argument<Int>("timeoutSec") ?: 45, reply)
        "cancelMeasure" -> { stopMeasurement(call.argument<String>("type")!!); reply.ok(null) }
        "startRealtimeHeartRate" -> { realtime.start(); reply.ok(null) }
        "stopRealtimeHeartRate" -> { realtime.stop(); reply.ok(null) }
        "workout" -> workout(call.argument<String>("action")!!, call.argument<Int>("type") ?: 7, reply)
        else -> reply.result.notImplemented()
      }
    } catch (t: Throwable) {
      reply.fail("native_error", t.message ?: t.toString())
    }
  }

  // ── Connection ──────────────────────────────────────────────────────────

  private val seen = HashSet<String>()

  private fun startScan(timeoutMs: Int, reply: Reply) {
    seen.clear()
    val scanner = BleScannerHelper.getInstance()
    scanner.reSetCallback()
    scanner.scanDevice(context, null, object : ScanWrapperCallback {
      override fun onStart() {}
      override fun onStop() { emit(mapOf("event" to "scanStopped")) }
      override fun onLeScan(device: BluetoothDevice?, rssi: Int, scanRecord: ByteArray?) {
        val name = try { device?.name } catch (_: SecurityException) { null }
        if (device == null || name.isNullOrEmpty() || !seen.add(device.address)) return
        emit(mapOf("event" to "scanResult", "id" to device.address, "mac" to device.address,
          "name" to name, "rssi" to rssi))
      }
      override fun onScanFailed(errorCode: Int) { emit(mapOf("event" to "scanStopped", "error" to errorCode)) }
      override fun onParsedData(device: BluetoothDevice?, scanRecord: ScanRecord?) {}
      override fun onBatchScanResults(results: MutableList<ScanResult>?) {}
    })
    main.postDelayed(stopScanRunnable, timeoutMs.toLong())
    reply.ok(null)
  }

  private val stopScanRunnable = Runnable { stopScan() }

  private fun stopScan() {
    main.removeCallbacks(stopScanRunnable)
    BleScannerHelper.getInstance().stopScan(context)
    emit(mapOf("event" to "scanStopped"))
  }

  private fun connect(mac: String, reply: Reply) {
    stopScan()
    DeviceManager.getInstance().deviceAddress = mac
    BleOperateManager.getInstance().setReConnectMac(mac)
    emit(mapOf("event" to "connection", "state" to "connecting", "id" to mac))
    BleOperateManager.getInstance().connectDirectly(mac)
    reply.ok(null)
  }

  private fun disconnect(unbind: Boolean, reply: Reply) {
    realtime.stop()
    val mgr = BleOperateManager.getInstance()
    if (unbind || supportBlePair) mgr.unBindDevice() else mgr.disconnect()
    if (unbind) DeviceManager.getInstance().reSet()
    reply.ok(null)
  }

  // ── Device ──────────────────────────────────────────────────────────────

  private fun syncTime(reply: Reply) {
    command<SetTimeRsp>(SetTimeReq(1), reply) { t ->
      // Extended capabilities come from a second request; ask before replying.
      CommandHandle.getInstance().executeReqCmd(DeviceSupportReq.getReadInstance(),
        ICommandResponse<DeviceSupportFunctionRsp> { s ->
          supportBlePair = s.supportBlePair
          if (s.supportBlePair) BleOperateManager.getInstance().bleCreateBond()
          reply.ok(features(t, s))
        })
      main.postDelayed({ reply.ok(features(t, null)) }, 4_000)
      Unit
    }
  }

  private fun features(t: SetTimeRsp, s: DeviceSupportFunctionRsp?): Map<String, Any> = mapOf(
    "heartRate" to t.supportsHeartRate(),
    "spo2" to (t.supportsBloodOxygen() || s?.supportIntervalBloodOxygen == true),
    "bloodPressure" to t.supportsBloodPressure(),
    "hrv" to t.supportsHrv(),
    "stress" to t.supportsPressure(),
    "temperature" to (t.supportsTemperature() || s?.supportSkinTemperature == true ||
      s?.supportIntervalTemperature == true),
    "appMeasure" to t.mSupportAppMeasure,
    "newSleep" to t.supportsSleepHistory(),
    "touch" to (s?.supportTouch == true),
  )

  private fun getBattery(reply: Reply) {
    command<BatteryRsp>(SimpleKeyReq(Constants.CMD_GET_DEVICE_ELECTRICITY_VALUE), reply) {
      mapOf("level" to it.batteryValue, "charging" to it.isCharging)
    }
  }

  private fun getVersions(reply: Reply) {
    // Versions arrive asynchronously on the GATT receiver; ask again and
    // answer with whatever is cached a moment later.
    val ch = CommandHandle.getInstance()
    ch.execReadCmd(ch.readFmRequest)
    ch.execReadCmd(ch.readHwRequest)
    main.postDelayed({ reply.ok(mapOf("firmware" to firmware, "hardware" to hardware)) }, 1_500)
  }

  private fun setUserProfile(call: MethodCall, reply: Reply) {
    val male = call.argument<Boolean>("male") ?: true
    val req = TimeFormatReq.getWriteInstance(
      call.argument<Boolean>("is24h") ?: true,
      if (call.argument<Boolean>("metric") != false) 0 else 1,
      if (male) 0 else 1,
      call.argument<Int>("age") ?: 30,
      call.argument<Int>("heightCm") ?: 170,
      call.argument<Int>("weightKg") ?: 70,
      0, 0, 0)
    fire(req, reply)
  }

  private fun setGoals(call: MethodCall, reply: Reply) {
    fire(TargetSettingReq.getWriteInstance(call.argument<Int>("steps") ?: 10_000,
      call.argument<Int>("kcal") ?: 500, call.argument<Int>("distanceM") ?: 8_000), reply)
  }

  private fun vibrate(call: MethodCall, reply: Reply) {
    val on = ((call.argument<Int>("onMs") ?: 200) / 100).coerceIn(1, 127)
    val off = ((call.argument<Int>("offMs") ?: 200) / 100).coerceIn(0, 255)
    val cycles = (call.argument<Int>("cycles") ?: 1).coerceIn(1, 255)
    fire(NotificationEventNotifyReq.getCustomVibrationInstance(
      200, NotificationEventNotifyReq.VIBRATION_START, cycles, on, off), reply)
  }

  private fun setTouchEvents(enabled: Boolean, reply: Reply) {
    // appType 9 = forward touch events to the app; 0 = off.
    fire(TouchControlReq.getWriteInstance(if (enabled) 9 else 0, true, 1, 1), reply)
  }

  private fun setAutoMeasure(call: MethodCall, reply: Reply) {
    val on = call.argument<Boolean>("enabled") ?: true
    val interval = call.argument<Int>("intervalMin") ?: 30
    val req: BaseReqCmd = when (call.argument<String>("metric")) {
      "heartRate" -> HeartRateSettingReq.getWriteInstance(on, interval)
      "spo2" -> BloodOxygenSettingReq.getWriteInstance(on, interval.coerceIn(1, 120).toByte())
      "hrv" -> HrvSettingReq(on, interval)
      "stress" -> PressureSettingReq.getWriteInstance(on, interval)
      "temperature" -> SugarLipidsSettingReq.getWriteTemperatureInstance(on, interval)
      else -> return reply.fail("bad_args", "unknown metric")
    }
    fire(req, reply)
  }

  // Day masks follow the vendor's Sunday-first order (bit0 = Sunday … bit6 =
  // Saturday); bit7 marks the entry as enabled. Weekdays arrive as ISO 1..7.
  private fun dayMask(call: MethodCall): Int =
    (call.argument<List<Int>>("days") ?: emptyList()).fold(0) { m, d -> m or (1 shl (d % 7)) }

  private fun window(start: Int, end: Int) = StartEndTimeEntity(start / 60, start % 60, end / 60, end % 60)

  private fun setAlarm(call: MethodCall, reply: Reply) {
    if (!BleOperateManager.getInstance().isConnected) return reply.fail("not_connected", "ring is not connected")
    val enabled = call.argument<Boolean>("enabled") ?: false
    val bean = AlarmNewEntity.AlarmBean().apply {
      content = "Helium"
      min = call.argument<Int>("minute") ?: 420
      repeatAndEnable = dayMask(call) or (if (enabled) 0x80 else 0)
      alarmLength = 4 + content.encodeToByteArray().size
    }
    LargeDataHandler.getInstance().writeAlarm(AlarmNewEntity().apply { total = 1; data = mutableListOf(bean) })
    reply.ok(null)
  }

  private fun getAlarms(reply: Reply) {
    if (!BleOperateManager.getInstance().isConnected) return reply.fail("not_connected", "ring is not connected")
    LargeDataHandler.getInstance().readAlarmWithCallback(IReadAlarmCallback { e ->
      reply.ok(e?.data.orEmpty().map {
        mapOf("minute" to it.min, "repeatAndEnable" to it.repeatAndEnable, "label" to (it.content ?: ""))
      })
    })
    main.postDelayed({ reply.fail("timeout", "ring did not return alarms") }, 8_000)
  }

  private fun setSedentary(call: MethodCall, reply: Reply) {
    val enabled = call.argument<Boolean>("enabled") ?: false
    val mask = if (enabled) dayMask(call) or 0x80 else 0
    val interval = (call.argument<Int>("intervalMin") ?: 60).coerceIn(15, 255)
    fire(SetSitLongReq(window(call.argument<Int>("start") ?: 540, call.argument<Int>("end") ?: 1260),
      mask.toByte(), interval), reply)
  }

  private fun startOta(path: String, reply: Reply) {
    val dfu = DfuHandle.getInstance()
    dfu.initCallback()
    if (!dfu.checkFile(path)) return reply.fail("bad_file", "not a valid firmware file: $path")
    dfu.start(object : DfuHandle.IOpResult {
      override fun onActionResult(type: Int, errCode: Int) {
        if (errCode != DfuHandle.RSP_OK) {
          dfu.endAndRelease()
          emit(mapOf("event" to "ota", "percent" to 0, "done" to true,
            "error" to if (errCode == DfuHandle.RSP_LOW_BATTERY) "low_battery" else "code_$errCode"))
          return
        }
        when (type) {
          1 -> dfu.init()
          2 -> dfu.sendPacket()
          3 -> dfu.check()
          4 -> { dfu.endAndRelease(); emit(mapOf("event" to "ota", "percent" to 100, "done" to true)) }
        }
      }
      override fun onProgress(percent: Int) { emit(mapOf("event" to "ota", "percent" to percent)) }
    }, false)
    reply.ok(null)
  }

  // ── History ─────────────────────────────────────────────────────────────

  private fun getActivitySummary(day: Int, reply: Reply) {
    if (day == 0) {
      command<TodaySportDataRsp>(SimpleKeyReq(Constants.CMD_GET_STEP_TODAY), reply) {
        val t = it.sportTotal
        mapOf("steps" to t.totalSteps, "distanceM" to t.walkDistance,
          "kcal" to t.calorie / 1000.0, "activeMin" to minutes(t.sportDuration))
      }
      return
    }
    BleOperateManager.getInstance().getStepDetail(day, health(reply) { list: List<BleStepDetails> ->
      mapOf("steps" to list.sumOf { it.walkSteps + it.runSteps },
        "distanceM" to list.sumOf { it.distance },
        "kcal" to list.sumOf { it.calorie } / 1000.0,
        "activeMin" to list.count { it.walkSteps + it.runSteps > 300 } * 15)
    })
  }

  private fun getActivityDetail(day: Int, reply: Reply) {
    val base = midnight(day)
    BleOperateManager.getInstance().getStepDetail(day, health(reply) { list: List<BleStepDetails> ->
      list.map {
        mapOf("ts" to base + it.timeIndex * 15 * MINUTE, "steps" to it.walkSteps + it.runSteps,
          "distanceM" to it.distance, "kcal" to it.calorie / 1000.0)
      }
    })
  }

  private fun getHeartRate(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getHeartRate(day, health(reply) { r: ReadHeartRateRsp ->
      series(day, r.interval.takeIf { it > 0 } ?: 5, r.array.orEmpty().map { it.toDouble() })
    })
  }

  private fun getSpO2(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getBloodOxygen(day, health(reply) { r: BloodOxygenEntity ->
      series(day, r.interval.takeIf { it > 0 } ?: 60, r.array.orEmpty().map { it.toDouble() })
    })
  }

  private fun getHrv(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getHrv(day, health(reply) { r: HRVRsp ->
      series(day, r.range.takeIf { it > 0 } ?: 30, r.hrvArray.toUnsigned())
    })
  }

  private fun getStress(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getPressure(day, health(reply) { r: PressureRsp ->
      series(day, r.range.takeIf { it > 0 } ?: 30, r.pressureArray.toUnsigned())
    })
  }

  private fun getTemperature(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getTemperature(day, health(reply) { r: IntervalTemperatureEntity ->
      series(day, r.interval.takeIf { it > 0 } ?: 30, r.array.orEmpty().map { it.toDouble() })
    })
  }

  private fun getBloodPressure(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getBloodPressure(day, health(reply) { list: List<BlePressure> ->
      list.filter { it.sbp > 0 }.map { mapOf("ts" to toMs(it.time), "sys" to it.sbp, "dia" to it.dbp) }
    })
  }

  private fun getSleep(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getSleep(day, health(reply) { s: SleepDisplay -> sleepMap(s) })
  }

  private fun sleepMap(s: SleepDisplay): Map<String, Any>? {
    val segs = s.list.orEmpty().filter { it.sleepEnd > it.sleepStart }
    if (segs.isEmpty()) return null
    // Durations are rebuilt from segments: the summary fields' units vary by firmware.
    val minutes = IntArray(5)
    val out = segs.map {
      val stage = when (it.type) { 1 -> "deep"; 2 -> "light"; 3 -> "awake"; 4 -> "rem"; else -> "unknown" }
      val start = toMs(it.sleepStart); val end = toMs(it.sleepEnd)
      val idx = when (stage) { "deep" -> 0; "light" -> 1; "rem" -> 2; "awake" -> 3; else -> 4 }
      minutes[idx] += ((end - start) / MINUTE).toInt()
      mapOf("start" to start, "end" to end, "stage" to stage)
    }
    return mapOf(
      "start" to (out.first()["start"] as Long), "end" to (out.last()["end"] as Long),
      "deepMin" to minutes[0], "lightMin" to minutes[1], "remMin" to minutes[2], "awakeMin" to minutes[3],
      "totalMin" to minutes[0] + minutes[1] + minutes[2], "score" to s.sleepScore, "segments" to out)
  }

  private fun getWorkouts(day: Int, reply: Reply) {
    BleOperateManager.getInstance().getSport(day, health(reply) { list: List<SportPlusEntity> ->
      list.map {
        mapOf("type" to it.mSportType, "start" to toMs(it.mStartTime.toLong()),
          "durationSec" to it.mDuration, "distanceM" to it.mDistance, "kcal" to it.mCalories / 1000.0,
          "avgHr" to it.mRateAvg, "minHr" to it.mRateMin, "maxHr" to it.mRateMax, "steps" to it.steps)
      }
    })
  }

  // ── Measurement ─────────────────────────────────────────────────────────

  private var activeMeasurement: String? = null

  private fun manual(type: String, cb: ICommandResponse<StartHeartRateRsp>, stop: Boolean) {
    val m = BleOperateManager.getInstance()
    when (type) {
      "heartRate" -> m.manualModeHeart(cb, stop)
      "spo2" -> m.manualModeSpO2(cb, stop)
      "bloodPressure" -> m.manualModeBP(cb, stop)
      "hrv" -> m.manualModeHrv(cb, stop)
      "stress" -> m.manualModePressure(cb, stop)
      "temperature" -> m.manualTemperature(cb, stop)
      else -> throw IllegalArgumentException("unknown measurement $type")
    }
  }

  private fun stopMeasurement(type: String) {
    if (activeMeasurement == type) activeMeasurement = null
    manual(type, ICommandResponse { }, true)
  }

  private fun measure(type: String, timeoutSec: Int, reply: Reply) {
    activeMeasurement = type
    var latest: Map<String, Any>? = null
    var settling = false
    val finish = Runnable {
      stopMeasurement(type)
      latest?.let { reply.ok(it) } ?: reply.fail("timeout", "no valid $type reading (is the ring worn?)")
    }
    manual(type, ICommandResponse { rsp ->
      main.post {
        if (activeMeasurement != type) return@post
        if (rsp.status != BaseRspCmd.RESULT_OK || rsp.errCode.toInt() != 0) {
          main.removeCallbacks(finish)
          stopMeasurement(type)
          reply.fail("measure_failed", "ring reported error ${rsp.errCode}")
          return@post
        }
        val reading = reading(type, rsp) ?: return@post
        latest = reading
        emit(mapOf("event" to "measurementProgress", "type" to type, "value" to reading["value"]!!))
        // Readings keep refining for a few seconds; settle before answering.
        if (!settling) {
          settling = true
          main.removeCallbacks(finish)
          main.postDelayed(finish, 4_000)
        }
      }
    }, false)
    main.postDelayed(finish, timeoutSec * 1000L)
  }

  private fun reading(type: String, r: StartHeartRateRsp): Map<String, Any>? = when (type) {
    "heartRate" -> (if (r.heartRate > 0) r.heartRate else r.value).takeIf { it > 0 }?.let { mapOf("value" to it) }
    "spo2" -> (if (r.bloodOxygen > 0) r.bloodOxygen else r.value).takeIf { it in 70..100 }?.let { mapOf("value" to it) }
    "bloodPressure" -> if (r.sbp > 0 && r.dbp > 0) mapOf("value" to r.sbp, "sys" to r.sbp, "dia" to r.dbp) else null
    "hrv" -> (if (r.hrv > 0) r.hrv else r.value).takeIf { it > 0 }?.let { mapOf("value" to it) }
    "stress" -> (if (r.stress > 0) r.stress else r.value).takeIf { it > 0 }?.let { mapOf("value" to it) }
    "temperature" -> {
      val raw = if (r.temperature > 0) r.temperature else r.value
      // Firmware reports hundredths or tenths of a degree.
      val c = when { raw > 1000 -> raw / 100.0; raw > 100 -> raw / 10.0; else -> raw.toDouble() }
      c.takeIf { it in 25.0..45.0 }?.let { mapOf("value" to it) }
    }
    else -> null
  }

  /** Continuous heart rate: start (1), poll (3) every 2 s, stop (2). */
  private val realtime = object {
    var running = false
    val poll: Runnable = Runnable {
      if (running) {
        CommandHandle.getInstance().executeReqCmd(RealTimeHeartRate(0x03), ICommandResponse<RealTimeHeartRateRsp> { r -> onBeat(r) })
      }
    }

    fun onBeat(r: RealTimeHeartRateRsp?) {
      main.post {
        if (!running) return@post
        if (r == null || r.status != BaseRspCmd.RESULT_OK) { stop(); return@post }
        if (r.heart > 0) emit(mapOf("event" to "realtimeHeartRate", "bpm" to r.heart))
        main.postDelayed(poll, 2_000)
      }
    }

    fun start() {
      if (running) return
      running = true
      CommandHandle.getInstance().executeReqCmd(RealTimeHeartRate(0x01), ICommandResponse<RealTimeHeartRateRsp> { r -> onBeat(r) })
    }

    fun stop() {
      if (!running) return
      running = false
      main.removeCallbacks(poll)
      CommandHandle.getInstance().executeReqCmdNoCallback(RealTimeHeartRate(0x02))
    }
  }

  private fun workout(action: String, type: Int, reply: Reply) {
    val status = when (action) { "start" -> 1; "pause" -> 2; "resume" -> 3; "stop" -> 4; else -> 0 }
    if (status == 0) return reply.fail("bad_args", "unknown action $action")
    fire(PhoneSportReq.getSportStatus(status.toByte(), type.toByte()), reply)
  }

  // ── Plumbing ────────────────────────────────────────────────────────────

  /** Completes a Flutter result once, on the main thread. */
  private class Reply(val result: MethodChannel.Result) {
    private val done = AtomicBoolean(false)
    fun ok(value: Any?) { if (done.compareAndSet(false, true)) main.post { result.success(value) } }
    fun fail(code: String, msg: String) { if (done.compareAndSet(false, true)) main.post { result.error(code, msg, null) } }
  }

  private fun <T : BaseRspCmd> command(req: BaseReqCmd, reply: Reply, timeoutMs: Long = 8_000, map: (T) -> Any?) {
    if (!BleOperateManager.getInstance().isConnected) return reply.fail("not_connected", "ring is not connected")
    CommandHandle.getInstance().executeReqCmd(req, ICommandResponse<T> { rsp ->
      if (rsp == null || rsp.status != BaseRspCmd.RESULT_OK) reply.fail("command_failed", "status ${rsp?.status}")
      else try { val v = map(rsp); if (v != Unit) reply.ok(v) } catch (t: Throwable) { reply.fail("parse_error", t.toString()) }
    })
    main.postDelayed({ reply.fail("timeout", "ring did not answer ${req.javaClass.simpleName}") }, timeoutMs)
  }

  /** Fire-and-forget write: the ring does not always acknowledge settings. */
  private fun fire(req: BaseReqCmd, reply: Reply) {
    if (!BleOperateManager.getInstance().isConnected) return reply.fail("not_connected", "ring is not connected")
    CommandHandle.getInstance().executeReqCmd(req, null)
    reply.ok(null)
  }

  private fun <T> health(reply: Reply, timeoutMs: Long = 30_000, map: (T) -> Any?): BleOperateManager.HealthDataCallback<T> {
    main.postDelayed({ reply.fail("timeout", "ring did not return history") }, timeoutMs)
    return object : BleOperateManager.HealthDataCallback<T> {
      override fun onSuccess(data: T) {
        try { reply.ok(if (data == null) null else map(data)) } catch (t: Throwable) { reply.fail("parse_error", t.toString()) }
      }
      override fun onError(code: Int, message: String?) { reply.fail("sdk_$code", message ?: "history query failed") }
    }
  }

  private fun series(day: Int, intervalMin: Int, values: List<Double>): List<Map<String, Any>> {
    val base = midnight(day)
    return values.mapIndexedNotNull { i, v ->
      if (v <= 0.0) null else mapOf("ts" to base + i * intervalMin * MINUTE, "value" to v)
    }
  }

  private fun day(call: MethodCall) = call.argument<Int>("day") ?: 0

  private fun ByteArray?.toUnsigned(): List<Double> = this?.map { (it.toInt() and 0xFF).toDouble() } ?: emptyList()

  companion object {
    private const val MINUTE = 60_000L
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var eventSink: EventChannel.EventSink? = null
    private var initialized = false
    private var supportBlePair = false
    private var firmware = ""
    private var hardware = ""
    private const val NOTIFY_KEY = 0x5151
    private const val SPORT_KEY = 0x78

    fun emit(event: Map<String, Any?>) = main.post { eventSink?.success(event) }

    private fun midnight(day: Int): Long = Calendar.getInstance().apply {
      set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
      add(Calendar.DAY_OF_YEAR, -day)
    }.timeInMillis

    /** Ring timestamps are seconds on most firmware, milliseconds on some. */
    private fun toMs(v: Long) = if (v in 1 until 100_000_000_000L) v * 1000 else v

    private fun minutes(v: Int) = if (v > 24 * 60) v / 60 else v

    private fun be(b: ByteArray, from: Int, len: Int): Int {
      var v = 0
      for (i in from until from + len) v = (v shl 8) or (b.getOrNull(i)?.toInt()?.and(0xFF) ?: 0)
      return v
    }

    /** One-time SDK setup; must run before any connect (see SDK docs §1.3). */
    private fun initSdk(app: Application) {
      if (initialized) return
      initialized = true
      ContextCompat.registerReceiver(app, GattReceiver(), BleAction.getIntentFilter(), ContextCompat.RECEIVER_NOT_EXPORTED)
      BleOperateManager.getInstance(app)
      BleOperateManager.getInstance().init()
      ContextCompat.registerReceiver(app, AdapterReceiver(), BleAction.getDeviceIntentFilter(), ContextCompat.RECEIVER_EXPORTED)
    }

    private fun onReady() {
      LargeDataHandler.getInstance().initEnable()
      val mgr = BleOperateManager.getInstance()
      mgr.addOutDeviceListener(NOTIFY_KEY, NotifyListener())
      mgr.addSportDeviceListener(SPORT_KEY, SportListener())
      // The SDK asks for a short pause before the first command.
      main.postDelayed({
        emit(mapOf("event" to "connection", "state" to "ready", "id" to DeviceManager.getInstance().deviceAddress))
        CommandHandle.getInstance().executeReqCmd(SimpleKeyReq(Constants.CMD_BIND_SUCCESS), null)
      }, 600)
    }
  }

  /** SDK GATT callbacks (connection, ready, characteristic reads). */
  class GattReceiver : QCBluetoothCallbackCloneReceiver() {
    override fun connectStatue(device: BluetoothDevice?, connected: Boolean) {
      if (device != null && connected) {
        DeviceManager.getInstance().deviceAddress = device.address
        emit(mapOf("event" to "connection", "state" to "connected", "id" to device.address))
      } else {
        emit(mapOf("event" to "connection", "state" to "disconnected", "id" to device?.address))
      }
    }

    override fun onServiceDiscovered() = onReady()

    override fun onCharacteristicRead(uuid: String?, data: ByteArray?) {
      if (uuid == null || data == null) return
      val v = String(data, Charsets.UTF_8).trim { it <= ' ' }
      when (uuid) {
        Constants.CHAR_FIRMWARE_REVISION.toString() -> firmware = v
        Constants.CHAR_HW_REVISION.toString() -> hardware = v
        else -> return
      }
      emit(mapOf("event" to "versions", "firmware" to firmware, "hardware" to hardware))
    }

    override fun onCharacteristicChange(address: String?, uuid: String?, data: ByteArray?) {}
  }

  /** Phone Bluetooth on/off. Note the SDK's flag is inverted (false = turned off). */
  class AdapterReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
      when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
        BluetoothAdapter.STATE_OFF -> {
          BleOperateManager.getInstance().setBluetoothTurnOff(false)
          emit(mapOf("event" to "bluetooth", "on" to false))
        }
        BluetoothAdapter.STATE_ON -> {
          BleOperateManager.getInstance().setBluetoothTurnOff(true)
          emit(mapOf("event" to "bluetooth", "on" to true))
          val mac = DeviceManager.getInstance().deviceAddress
          if (!mac.isNullOrEmpty()) {
            BleOperateManager.getInstance().setReConnectMac(mac)
            BleOperateManager.getInstance().connectDirectly(mac)
          }
        }
      }
    }
  }

  /** Unsolicited device reports: battery, live steps, touch, "new data". */
  class NotifyListener : DeviceNotifyListener() {
    override fun onDataResponse(rsp: DeviceNotifyRsp?) {
      super.onDataResponse(rsp)
      if (rsp == null || rsp.status != BaseRspCmd.RESULT_OK) return
      val d = rsp.loadData ?: return
      when (rsp.unsignedDataType) {
        DeviceNotifyRsp.TYPE_BATTERY -> emit(mapOf("event" to "battery", "level" to be(d, 1, 1),
          "charging" to (be(d, 2, 1) == DeviceNotifyRsp.CHARGE_STATUS_CHARGING)))
        DeviceNotifyRsp.TYPE_STEP_CALORIE_DISTANCE -> emit(mapOf("event" to "dataUpdated", "kind" to "steps",
          "steps" to be(d, 1, 3), "kcal" to be(d, 4, 3) / 1000.0, "distanceM" to be(d, 7, 3)))
        DeviceNotifyRsp.TYPE_CUSTOM_BUTTON_FUNCTION -> emit(mapOf("event" to "touch", "gesture" to when (be(d, 1, 1)) {
          1 -> "swipeDown"; 2 -> "swipeUp"; 3 -> "tap"; 4 -> "longPress"; else -> "unknown" }))
        DeviceNotifyRsp.TYPE_HEART_RATE -> emit(mapOf("event" to "dataUpdated", "kind" to "heartRate"))
        DeviceNotifyRsp.TYPE_BLOOD_OXYGEN -> emit(mapOf("event" to "dataUpdated", "kind" to "spo2"))
        DeviceNotifyRsp.TYPE_BODY_TEMPERATURE -> emit(mapOf("event" to "dataUpdated", "kind" to "temperature"))
        DeviceNotifyRsp.TYPE_SLEEP -> emit(mapOf("event" to "dataUpdated", "kind" to "sleep"))
        DeviceNotifyRsp.TYPE_SPORT_RECORD -> emit(mapOf("event" to "dataUpdated", "kind" to "workout"))
        DeviceNotifyRsp.TYPE_HRV -> emit(mapOf("event" to "dataUpdated", "kind" to "hrv"))
        DeviceNotifyRsp.TYPE_PRESSURE -> emit(mapOf("event" to "dataUpdated", "kind" to "stress"))
      }
    }
  }

  /** Live workout data while a ring-side workout runs. */
  class SportListener : DeviceSportNotifyListener() {
    override fun onDataResponse(rsp: DeviceNotifyRsp?) {
      super.onDataResponse(rsp)
      val d = rsp?.loadData ?: return
      emit(mapOf("event" to "workout", "state" to be(d, 1, 1), "durationSec" to be(d, 2, 2),
        "heartRate" to be(d, 4, 1), "steps" to be(d, 5, 3), "distanceM" to be(d, 8, 3),
        "kcal" to be(d, 11, 3) / 1000.0))
    }
  }
}
