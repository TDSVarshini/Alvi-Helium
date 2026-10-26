#import "QringSdkPlugin.h"

#import <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR

#import <CoreBluetooth/CoreBluetooth.h>
#import <QCBandSDK/QCBandSDK.h>
#import <QCBandSDK/QCSDKManager.h>
#import <QCBandSDK/QCSDKCmdCreator.h>
#import <QCBandSDK/QCDFU_Utils.h>
#import <QCBandSDK/QCSportModel.h>
#import <QCBandSDK/QCSleepModel.h>
#import <QCBandSDK/QCSchedualHeartRateModel.h>
#import <QCBandSDK/QCBloodOxygenModel.h>
#import <QCBandSDK/QCBloodPressureModel.h>
#import <QCBandSDK/QCTemperatureModel.h>
#import <QCBandSDK/QCHRVDayModel.h>
#import <QCBandSDK/QCHRVSampleModel.h>
#import <QCBandSDK/QCPressureDayModel.h>
#import <QCBandSDK/QCPressureSampleModel.h>
#import <QCBandSDK/QCSportInfoModel.h>
#import <QCBandSDK/OdmSportPlusModels.h>
#import <QCBandSDK/QCAlarmModel.h>

static NSString *const kLastPeripheralKey = @"qring_sdk.lastPeripheral";
static const NSTimeInterval kHoldRealtimeEvery = 20;

/// A reply that can only be sent once, always on the main queue.
@interface QRReply : NSObject
@property(nonatomic, copy) FlutterResult result;
@property(nonatomic, copy) dispatch_block_t onDone;
@property(atomic, assign) BOOL done;
- (void)ok:(id)value;
- (void)fail:(NSString *)code message:(NSString *)message;
@end

@implementation QRReply
- (BOOL)claim {
  @synchronized(self) {
    if (self.done) return NO;
    self.done = YES;
    return YES;
  }
}
- (void)ok:(id)value {
  if (![self claim]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.result(value);
    if (self.onDone) self.onDone();
  });
}
- (void)fail:(NSString *)code message:(NSString *)message {
  if (![self claim]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.result([FlutterError errorWithCode:code message:message details:nil]);
    if (self.onDone) self.onDone();
  });
}
@end

typedef void (^QRJob)(QRReply *reply);

@interface QringSdkPlugin () <CBCentralManagerDelegate>
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) CBPeripheral *peripheral;
@property(nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *discovered;
@property(nonatomic, copy) NSString *pendingConnectId;
@property(nonatomic, assign) BOOL userDisconnected;
@property(nonatomic, assign) BOOL ready;
@property(nonatomic, copy) FlutterEventSink sink;
@property(nonatomic, strong) NSTimer *scanTimer;
@property(nonatomic, strong) NSTimer *holdTimer;
@property(nonatomic, strong) NSMutableArray<NSArray *> *queue;  // @[job, timeout]
@property(nonatomic, assign) BOOL busy;
@end

@implementation QringSdkPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  QringSdkPlugin *plugin = [QringSdkPlugin new];
  FlutterMethodChannel *methods = [FlutterMethodChannel methodChannelWithName:@"qring_sdk/methods"
                                                              binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:plugin channel:methods];
  FlutterEventChannel *events = [FlutterEventChannel eventChannelWithName:@"qring_sdk/events"
                                                          binaryMessenger:[registrar messenger]];
  [events setStreamHandler:plugin];
}

- (instancetype)init {
  if ((self = [super init])) {
    _discovered = [NSMutableDictionary new];
    _queue = [NSMutableArray new];
#ifndef DEBUG
    [QCSDKManager shareInstance].debug = NO;
#endif
    [self installLiveCallbacks];
  }
  return self;
}

#pragma mark - Events

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  self.sink = events;
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  self.sink = nil;
  return nil;
}

- (void)emit:(NSDictionary *)event {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.sink) self.sink(event);
  });
}

- (void)emitState:(NSString *)state {
  [self emit:@{@"event" : @"connection", @"state" : state,
               @"id" : self.peripheral.identifier.UUIDString ?: [NSNull null]}];
}

/// QCSDKManager exposes single-slot blocks; set them once here and fan out.
- (void)installLiveCallbacks {
  __weak typeof(self) weakSelf = self;
  QCSDKManager *sdk = [QCSDKManager shareInstance];
  sdk.realTimeHeartRate = ^(NSInteger hr) {
    if (hr > 0) [weakSelf emit:@{@"event" : @"realtimeHeartRate", @"bpm" : @(hr)}];
  };
  sdk.currentStepInfo = ^(NSInteger step, NSInteger calorie, NSInteger distance) {
    [weakSelf emit:@{@"event" : @"dataUpdated", @"kind" : @"steps", @"steps" : @(step),
                     @"kcal" : @([QringSdkPlugin kcal:calorie]), @"distanceM" : @(distance)}];
  };
  sdk.currentBatteryInfo = ^(NSInteger battery, BOOL charging) {
    [weakSelf emit:@{@"event" : @"battery", @"level" : @(battery), @"charging" : @(charging)}];
  };
  sdk.currentSportInfo = ^(QCSportInfoModel *info) {
    [weakSelf emit:@{@"event" : @"workout", @"state" : @(info.state), @"durationSec" : @(info.duration),
                     @"heartRate" : @(info.hr), @"steps" : @(info.step), @"distanceM" : @(info.distance),
                     @"kcal" : @([QringSdkPlugin kcal:info.calorie])}];
  };
  sdk.watchDataUpdateReport = ^(QCDeviceDataUpdateReport type, NSInteger value) {
    NSString *kind = nil;
    switch (type) {
      case QCDeviceDataUpdateCustomKey: {
        NSArray *g = @[ @"unknown", @"swipeDown", @"swipeUp", @"tap", @"longPress" ];
        [weakSelf emit:@{@"event" : @"touch", @"gesture" : (value >= 0 && value < 5) ? g[value] : @"unknown"}];
        return;
      }
      case QCDeviceDataUpdateHeartRate: kind = @"heartRate"; break;
      case QCDeviceDataUpdateBloodOxygen: kind = @"spo2"; break;
      case QCDeviceDataUpdateBloodPressure: kind = @"bloodPressure"; break;
      case QCDeviceDataUpdateTemperature: kind = @"temperature"; break;
      case QCDeviceDataUpdateSleep: kind = @"sleep"; break;
      case QCDeviceDataUpdateSportRecord: kind = @"workout"; break;
      case QCDeviceDataUpdateStep:
      case QCDeviceDataUpdateStepInfo: kind = @"steps"; break;
      case QCDeviceDataUpdateHRV: kind = @"hrv"; break;
      case QCDeviceDataUpdateStress: kind = @"stress"; break;
      default: return;
    }
    [weakSelf emit:@{@"event" : @"dataUpdated", @"kind" : kind}];
  };
}

#pragma mark - Command queue

/// QCBandSDK fails concurrent commands (ChannelBusy 1001), so every call runs
/// one at a time, each with its own timeout because some never answer.
- (void)enqueue:(FlutterResult)result timeout:(NSTimeInterval)timeout job:(QRJob)job {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.queue addObject:@[ [job copy], result, @(timeout) ]];
    [self pump];
  });
}

- (void)pump {
  if (self.busy || self.queue.count == 0) return;
  NSArray *next = self.queue.firstObject;
  [self.queue removeObjectAtIndex:0];
  self.busy = YES;
  QRJob job = next[0];
  QRReply *reply = [QRReply new];
  reply.result = next[1];
  __weak typeof(self) weakSelf = self;
  reply.onDone = ^{
    weakSelf.busy = NO;
    [weakSelf pump];
  };
  if (!self.ready) {
    [reply fail:@"not_connected" message:@"ring is not connected"];
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([next[2] doubleValue] * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [reply fail:@"timeout" message:@"ring did not answer"];
                 });
  job(reply);
}

#pragma mark - Method calls

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *a = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : @{};
  NSInteger day = [a[@"day"] integerValue];
  NSString *m = call.method;

  if ([m isEqualToString:@"startScan"]) return [self startScan:[a[@"timeoutMs"] doubleValue] / 1000.0 result:result];
  if ([m isEqualToString:@"stopScan"]) { [self stopScan]; return result(nil); }
  if ([m isEqualToString:@"connect"]) { [self connect:a[@"id"]]; return result(nil); }
  if ([m isEqualToString:@"disconnect"]) { [self disconnectForget:NO]; return result(nil); }
  if ([m isEqualToString:@"unbind"]) { [self disconnectForget:YES]; return result(nil); }
  if ([m isEqualToString:@"isConnected"]) return result(@(self.ready));
  if ([m isEqualToString:@"startRealtimeHeartRate"]) return [self realtime:YES result:result];
  if ([m isEqualToString:@"stopRealtimeHeartRate"]) return [self realtime:NO result:result];
  if ([m isEqualToString:@"cancelMeasure"]) {
    [[QCSDKManager shareInstance] stopToMeasuringWithOperateType:[self measuringType:a[@"type"]]
                                                 completedHandle:^(BOOL ok, NSError *e) {}];
    return result(nil);
  }

  QRJob job = [self jobFor:m args:a day:day];
  if (!job) return result(FlutterMethodNotImplemented);
  NSTimeInterval timeout = [m hasPrefix:@"get"] && ![m isEqualToString:@"getBattery"] ? 30 : 10;
  if ([m isEqualToString:@"measure"]) timeout = [a[@"timeoutSec"] doubleValue] + 10;
  if ([m isEqualToString:@"startOta"]) timeout = 600;
  [self enqueue:result timeout:timeout job:job];
}

- (QRJob)jobFor:(NSString *)m args:(NSDictionary *)a day:(NSInteger)day {
  __weak typeof(self) weakSelf = self;

  if ([m isEqualToString:@"syncTime"]) return ^(QRReply *r) {
    [QCSDKCmdCreator setTime:[NSDate date]
        success:^(NSDictionary *f) {
          BOOL (^on)(NSString *) = ^BOOL(NSString *k) { return [f[k] boolValue]; };
          [r ok:@{@"heartRate" : @YES, @"spo2" : @(on(QCBandFeatureBloodOxygen)),
                  @"bloodPressure" : @(on(QCBandFeatureBloodPressure)), @"hrv" : @(on(QCBandFeatureHRV)),
                  @"stress" : @(on(QCBandFeatureStress)), @"temperature" : @(on(QCBandFeatureTemperature)),
                  @"appMeasure" : @(on(QCBandFeatureAppManual)), @"newSleep" : @(on(QCBandFeatureNewSleepProtocol)),
                  @"touch" : @(on(QCBandFeatureTouchControl))}];
        }
        failed:^{ [r fail:@"command_failed" message:@"setTime failed"]; }];
  };

  if ([m isEqualToString:@"getBattery"]) return ^(QRReply *r) {
    [QCSDKCmdCreator readBatterySuccess:^(int battery, BOOL charging) {
      [r ok:@{@"level" : @(battery), @"charging" : @(charging)}];
    } failed:^{ [r fail:@"command_failed" message:@"battery read failed"]; }];
  };

  if ([m isEqualToString:@"getVersions"]) return ^(QRReply *r) {
    // First block argument is the hardware/model string, second the firmware.
    [QCSDKCmdCreator getDeviceSoftAndHardVersionSuccess:^(NSString *hard, NSString *soft) {
      [r ok:@{@"firmware" : soft ?: @"", @"hardware" : hard ?: @""}];
    } fail:^{ [r fail:@"command_failed" message:@"version read failed"]; }];
  };

  if ([m isEqualToString:@"setUserProfile"]) return ^(QRReply *r) {
    [QCSDKCmdCreator setTimeFormatTwentyfourHourFormat:a[@"is24h"] ? [a[@"is24h"] boolValue] : YES
        metricSystem:a[@"metric"] ? [a[@"metric"] boolValue] : YES
        gender:[a[@"male"] boolValue] ? 0 : 1
        age:[a[@"age"] integerValue]
        height:[a[@"heightCm"] integerValue]
        weight:[a[@"weightKg"] integerValue]
        sbpBase:0 dbpBase:0 hrAlarmValue:0
        success:^(BOOL a1, BOOL a2, NSInteger a3, NSInteger a4, NSInteger a5, NSInteger a6, NSInteger a7,
                  NSInteger a8, NSInteger a9) { [r ok:nil]; }
        fail:^{ [r fail:@"command_failed" message:@"profile write failed"]; }];
  };

  if ([m isEqualToString:@"setGoals"]) return ^(QRReply *r) {
    [QCSDKCmdCreator setStepTarget:[a[@"steps"] integerValue]
                     calorieTarget:[a[@"kcal"] integerValue]
                    distanceTarget:[a[@"distanceM"] integerValue]
               sportDurationTarget:0
               sleepDurationTarget:0
                           success:^{ [r ok:nil]; }
                              fail:^{ [r fail:@"command_failed" message:@"goal write failed"]; }];
  };

  if ([m isEqualToString:@"findDevice"]) return ^(QRReply *r) {
    [QCSDKCmdCreator lookupDeviceSuccess:^{ [r ok:nil]; }
                                    fail:^{ [r fail:@"command_failed" message:@"find failed"]; }];
  };

  if ([m isEqualToString:@"vibrate"]) return ^(QRReply *r) {
    NSInteger on = MAX(1, MIN(127, [a[@"onMs"] integerValue] / 100));
    NSInteger off = MAX(0, MIN(255, [a[@"offMs"] integerValue] / 100));
    NSInteger cycles = MAX(1, MIN(255, [a[@"cycles"] integerValue]));
    [QCSDKCmdCreator sendCustomVibrationNotificationWithPriority:200
                                                          action:QCNotificationVibrationActionStart
                                                      cycleCount:cycles
                                                 vibrateDuration:on
                                                   pauseDuration:off
                                                         success:^{ [r ok:nil]; }
                                                            fail:^{ [r fail:@"command_failed" message:@"vibrate failed"]; }];
  };

  if ([m isEqualToString:@"setTouchEvents"]) return ^(QRReply *r) {
    QCTouchGestureControlType type = [a[@"enabled"] boolValue] ? QCTouchGestureControlTypeTouchEvent
                                                               : QCTouchGestureControlTypeOff;
    [QCSDKCmdCreator setTouchControl:type strength:1 duration:1 finshed:^(NSError *error) {
      error ? [r fail:@"command_failed" message:error.localizedDescription] : [r ok:nil];
    }];
  };

  if ([m isEqualToString:@"setAutoMeasure"]) return ^(QRReply *r) {
    NSString *metric = a[@"metric"];
    BOOL on = [a[@"enabled"] boolValue];
    NSInteger interval = MAX(1, [a[@"intervalMin"] integerValue]);
    void (^okBlock)(void) = ^{ [r ok:nil]; };
    void (^failBlock)(void) = ^{ [r fail:@"command_failed" message:@"setting rejected"]; };
    void (^errBlock)(NSError *) = ^(NSError *e) { e ? failBlock() : okBlock(); };
    if ([metric isEqualToString:@"heartRate"]) {
      [QCSDKCmdCreator setSchedualHeartRateStatus:on interval:interval
                                          success:^(BOOL e, NSInteger i) { okBlock(); } fail:failBlock];
    } else if ([metric isEqualToString:@"spo2"]) {
      [QCSDKCmdCreator setSchedualBOInfoOn:on timeInterval:interval success:okBlock fail:failBlock];
    } else if ([metric isEqualToString:@"hrv"]) {
      [QCSDKCmdCreator setSchedualHRVStatus:on finshed:errBlock];
    } else if ([metric isEqualToString:@"stress"]) {
      [QCSDKCmdCreator setSchedualStressStatus:on finshed:errBlock];
    } else if ([metric isEqualToString:@"temperature"]) {
      [QCSDKCmdCreator setSchedualInfoType:SchedualInfoTypeBodyTemperator featureOn:on calibrate:0
                                  interval:interval success:okBlock fail:failBlock];
    } else {
      [r fail:@"bad_args" message:@"unknown metric"];
    }
  };

  if ([m isEqualToString:@"setAlarm"]) return ^(QRReply *r) {
    // weekDays runs Sunday→Saturday; Flutter sends ISO weekdays (1 = Monday).
    NSMutableArray *week = [@[ @"0", @"0", @"0", @"0", @"0", @"0", @"0" ] mutableCopy];
    for (NSNumber *d in a[@"days"]) week[d.integerValue % 7] = @"1";
    QCAlarmModel *alarm = [QCAlarmModel new];
    alarm.type = [a[@"enabled"] boolValue] ? ALARMOTHER : ALARMCLOSE;
    alarm.time = [a[@"minute"] integerValue];
    alarm.name = @"Helium";
    alarm.weekDays = week;
    [QCSDKCmdCreator setBandAlarms:@[ alarm ] finish:^(NSArray *applied, NSError *error) {
      error ? [r fail:@"command_failed" message:error.localizedDescription] : [r ok:nil];
    }];
  };

  if ([m isEqualToString:@"getAlarms"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getBandAlarmsWithFinish:^(NSArray<QCAlarmModel *> *alarms, NSError *error) {
      if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
      NSMutableArray *out = [NSMutableArray new];
      for (QCAlarmModel *x in alarms) {
        [out addObject:@{@"minute" : @(x.time), @"type" : @(x.type), @"label" : x.name ?: @"",
                         @"weekDays" : [x.weekDays componentsJoinedByString:@","] ?: @""}];
      }
      [r ok:out];
    }];
  };

  if ([m isEqualToString:@"setDoNotDisturb"]) return ^(QRReply *r) {
    [QCSDKCmdCreator setDontDisturbOn:[a[@"enabled"] boolValue]
                            beginTime:[QringSdkPlugin hhmm:[a[@"start"] integerValue]]
                              endTime:[QringSdkPlugin hhmm:[a[@"end"] integerValue]]
                              success:^(BOOL on, NSString *b, NSString *e) { [r ok:nil]; }
                                 fail:^{ [r fail:@"command_failed" message:@"DND write failed"]; }];
  };

  if ([m isEqualToString:@"setSedentaryReminder"]) return ^(QRReply *r) {
    BOOL on = [a[@"enabled"] boolValue];
    NSMutableArray *week = [@[ @0, @0, @0, @0, @0, @0, @0 ] mutableCopy];
    if (on) for (NSNumber *d in a[@"days"]) week[d.integerValue % 7] = @1;
    NSUInteger interval = (NSUInteger)MAX(15, MIN(255, [a[@"intervalMin"] integerValue]));
    [QCSDKCmdCreator setBeginTime:[QringSdkPlugin hhmm:[a[@"start"] integerValue]]
                          endTime:[QringSdkPlugin hhmm:[a[@"end"] integerValue]]
                      repeatModel:week
                     timeInterval:interval
                          success:^{ [r ok:nil]; }
                             fail:^{ [r fail:@"command_failed" message:@"sedentary write failed"]; }];
  };

  if ([m isEqualToString:@"factoryReset"]) return ^(QRReply *r) {
    [QCSDKCmdCreator resetBandToFacotrySuccess:^{ [r ok:nil]; }
                                          fail:^{ [r fail:@"command_failed" message:@"reset failed"]; }];
  };

  if ([m isEqualToString:@"startOta"]) return ^(QRReply *r) {
    NSData *data = [NSData dataWithContentsOfFile:a[@"path"]];
    if (!data.length) return [r fail:@"bad_file" message:@"cannot read firmware file"];
    [r ok:nil];  // progress is reported as events; free the queue for nothing else meanwhile
    [QCSDKCmdCreator syncOtaBinData:data
        start:^{ [weakSelf emit:@{@"event" : @"ota", @"percent" : @0}]; }
        percentage:^(int p) { [weakSelf emit:@{@"event" : @"ota", @"percent" : @(p)}]; }
        success:^(int seconds) { [weakSelf emit:@{@"event" : @"ota", @"percent" : @100, @"done" : @YES}]; }
        failed:^(NSError *e) {
          [weakSelf emit:@{@"event" : @"ota", @"percent" : @0, @"done" : @YES,
                           @"error" : e.localizedDescription ?: @"ota failed"}];
        }];
  };

  if ([m isEqualToString:@"getActivitySummary"]) return ^(QRReply *r) {
    if (day == 0) {
      [QCSDKCmdCreator getCurrentSportSucess:^(QCSportModel *s) {
        [r ok:@{@"steps" : @(s.totalStepCount), @"distanceM" : @(s.distance),
                @"kcal" : @([QringSdkPlugin kcal:s.calories]), @"activeMin" : @(s.activeTime)}];
      } failed:^{ [r fail:@"command_failed" message:@"activity read failed"]; }];
      return;
    }
    [QCSDKCmdCreator getSportDetailDataByDay:day sportDatas:^(NSArray<QCSportModel *> *list) {
      NSInteger steps = 0, dist = 0, active = 0;
      double cal = 0;
      for (QCSportModel *s in list) {
        steps += s.totalStepCount; dist += s.distance; cal += s.calories; active += s.activeTime;
      }
      [r ok:@{@"steps" : @(steps), @"distanceM" : @(dist), @"kcal" : @([QringSdkPlugin kcal:cal]),
              @"activeMin" : @(active)}];
    } fail:^{ [r fail:@"command_failed" message:@"activity read failed"]; }];
  };

  if ([m isEqualToString:@"getActivityDetail"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getSportDetailDataByDay:day sportDatas:^(NSArray<QCSportModel *> *list) {
      NSMutableArray *out = [NSMutableArray new];
      for (QCSportModel *s in list) {
        [out addObject:@{@"ts" : @([QringSdkPlugin msFromString:s.happenDate]), @"steps" : @(s.totalStepCount),
                         @"distanceM" : @(s.distance), @"kcal" : @([QringSdkPlugin kcal:s.calories])}];
      }
      [r ok:out];
    } fail:^{ [r fail:@"command_failed" message:@"activity read failed"]; }];
  };

  if ([m isEqualToString:@"getHeartRate"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getSchedualHeartRateDataWithDayIndexs:@[ @(day) ]
        success:^(NSArray<QCSchedualHeartRateModel *> *models) {
          NSMutableArray *out = [NSMutableArray new];
          for (QCSchedualHeartRateModel *hr in models) {
            double base = [QringSdkPlugin msFromString:[hr.date stringByAppendingString:@" 00:00:00"]];
            NSInteger step = hr.secondInterval > 0 ? hr.secondInterval : 300;
            [hr.heartRates enumerateObjectsUsingBlock:^(NSNumber *v, NSUInteger i, BOOL *stop) {
              if (v.integerValue > 0) [out addObject:@{@"ts" : @(base + i * step * 1000.0), @"value" : v}];
            }];
          }
          [r ok:out];
        }
        fail:^{ [r fail:@"command_failed" message:@"heart rate read failed"]; }];
  };

  if ([m isEqualToString:@"getSpO2"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getBloodOxygenDataWithIntervalByDayIndex:day
        finished:^(NSInteger interval, NSArray *values, NSError *error) {
          if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
          double base = [QringSdkPlugin midnightMs:day];
          NSInteger step = interval > 0 ? interval : 60;
          NSMutableArray *out = [NSMutableArray new];
          [values enumerateObjectsUsingBlock:^(id v, NSUInteger i, BOOL *stop) {
            if ([v isKindOfClass:NSNumber.class] && [v doubleValue] > 0) {
              [out addObject:@{@"ts" : @(base + i * step * 60000.0), @"value" : v}];
            } else if ([v isKindOfClass:QCBloodOxygenModel.class] && [(QCBloodOxygenModel *)v soa2] > 0) {
              QCBloodOxygenModel *o = v;
              [out addObject:@{@"ts" : @(o.date.timeIntervalSince1970 * 1000), @"value" : @(o.soa2)}];
            }
          }];
          [r ok:out];
        }];
  };

  if ([m isEqualToString:@"getHrv"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getHRVSamplesWithDayIndexes:@[ @(day) ]
        finished:^(NSArray<QCHRVDayModel *> *days, NSError *error) {
          if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
          NSMutableArray *out = [NSMutableArray new];
          for (QCHRVDayModel *d in days)
            for (QCHRVSampleModel *s in d.samples)
              if (s.value > 0) [out addObject:@{@"ts" : @(s.unixTimestamp * 1000.0), @"value" : @(s.value)}];
          [r ok:out];
        }];
  };

  if ([m isEqualToString:@"getStress"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getPressureSamplesWithDayIndexes:@[ @(day) ]
        finished:^(NSArray<QCPressureDayModel *> *days, NSError *error) {
          if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
          NSMutableArray *out = [NSMutableArray new];
          for (QCPressureDayModel *d in days)
            for (QCPressureSampleModel *s in d.samples)
              if (s.value > 0) [out addObject:@{@"ts" : @(s.unixTimestamp * 1000.0), @"value" : @(s.value)}];
          [r ok:out];
        }];
  };

  if ([m isEqualToString:@"getTemperature"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getSchedualTemperatureDataByDayIndex:day finished:^(NSArray *list, NSError *error) {
      if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
      NSMutableArray *out = [NSMutableArray new];
      for (id o in list) {
        if (![o isKindOfClass:QCTemperatureModel.class]) continue;
        QCTemperatureModel *t = o;
        if (t.temperature > 0)
          [out addObject:@{@"ts" : @(t.time.timeIntervalSince1970 * 1000), @"value" : @(t.temperature)}];
      }
      [r ok:out];
    }];
  };

  if ([m isEqualToString:@"getBloodPressure"]) return ^(QRReply *r) {
    // No per-day API on iOS: fetch recent history and keep the requested day.
    double from = [QringSdkPlugin midnightMs:day], to = from + 86400000.0;
    [QCSDKCmdCreator getSchedualBPHistoryDataWithSuccess:^(NSArray<QCBloodPressureModel *> *data) {
      NSMutableArray *out = [NSMutableArray new];
      for (QCBloodPressureModel *bp in data) {
        double ts = bp.date.timeIntervalSince1970 * 1000;
        if (ts >= from && ts < to && bp.systolicPressure > 0)
          [out addObject:@{@"ts" : @(ts), @"sys" : @(bp.systolicPressure), @"dia" : @(bp.diastolicPressure)}];
      }
      [r ok:out];
    } fail:^{ [r fail:@"command_failed" message:@"blood pressure read failed"]; }];
  };

  if ([m isEqualToString:@"getSleep"]) return ^(QRReply *r) {
    [QCSDKCmdCreator getFulldaySleepDetailDataByDay:day
        sleepDatas:^(NSArray<QCSleepModel *> *sleeps, NSArray<QCSleepModel *> *naps) {
          [r ok:[QringSdkPlugin sleepMap:sleeps]];
        }
        fail:^{ [r fail:@"command_failed" message:@"sleep read failed"]; }];
  };

  if ([m isEqualToString:@"getWorkouts"]) return ^(QRReply *r) {
    double from = [QringSdkPlugin midnightMs:day], to = from + 86400000.0;
    [QCSDKCmdCreator getSportRecordsFromLastTimeStamp:0
        finish:^(NSArray<OdmGeneralExerciseSummaryModel *> *list, NSError *error) {
          if (error) return [r fail:@"sdk_error" message:error.localizedDescription];
          // The vendor demo treats ring start times as UTC+8 wall-clock.
          NSInteger shift = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"].secondsFromGMT -
                            [NSTimeZone systemTimeZone].secondsFromGMT;
          NSMutableArray *out = [NSMutableArray new];
          for (OdmGeneralExerciseSummaryModel *w in list) {
            double start = (w.startTime + shift) * 1000.0;
            if (start < from || start >= to) continue;
            [out addObject:@{@"type" : @(w.exerciseType), @"start" : @(start), @"durationSec" : @(w.duration),
                             @"distanceM" : @(w.distance), @"kcal" : @([QringSdkPlugin kcal:w.calorie]),
                             @"avgHr" : @(w.averageHR), @"minHr" : @(w.lowestHR), @"maxHr" : @(w.highestHR),
                             @"steps" : @(w.steps)}];
          }
          [r ok:out];
        }];
  };

  if ([m isEqualToString:@"measure"]) return ^(QRReply *r) {
    NSString *type = a[@"type"];
    QCMeasuringType mt = [weakSelf measuringType:type];
    if (mt == QCMeasuringTypeUnkown) return [r fail:@"bad_args" message:@"unknown measurement"];
    [[QCSDKManager shareInstance] startToMeasuringWithOperateType:mt
        timeout:[a[@"timeoutSec"] integerValue]
        measuringHandle:^(id result) {
          if ([result isKindOfClass:NSNumber.class] && [result doubleValue] > 0)
            [weakSelf emit:@{@"event" : @"measurementProgress", @"type" : type, @"value" : result}];
        }
        completedHandle:^(BOOL ok, id result, NSError *error) {
          if (!ok) {
            NSString *msg = error.code == -3 ? @"ring is not worn properly" : (error.localizedDescription ?: @"measurement failed");
            return [r fail:@"measure_failed" message:msg];
          }
          if ([result isKindOfClass:NSDictionary.class]) {
            NSInteger sys = [result[@"sbp"] integerValue], dia = [result[@"dbp"] integerValue];
            return [r ok:@{@"value" : @(sys), @"sys" : @(sys), @"dia" : @(dia)}];
          }
          double v = [result isKindOfClass:NSNumber.class] ? [result doubleValue] : 0;
          if (v <= 0 || (mt == QCMeasuringTypeHRV && v == 141))
            return [r fail:@"timeout" message:@"no valid reading (is the ring worn?)"];
          [r ok:@{@"value" : @(v)}];
        }];
  };

  if ([m isEqualToString:@"workout"]) return ^(QRReply *r) {
    NSDictionary *states = @{@"start" : @(QCSportStateStart), @"pause" : @(QCSportStatePause),
                             @"resume" : @(QCSportStateContinue), @"stop" : @(QCSportStateStop)};
    NSNumber *state = states[a[@"action"]];
    if (!state) return [r fail:@"bad_args" message:@"unknown action"];
    [QCSDKCmdCreator operateSportModeWithType:(OdmSportPlusExerciseModelType)[a[@"type"] integerValue]
                                        state:(QCSportState)state.intValue
                                       finish:^(id res, NSError *error) {
                                         error ? [r fail:@"command_failed" message:error.localizedDescription]
                                               : [r ok:nil];
                                       }];
  };

  return nil;
}

- (QCMeasuringType)measuringType:(NSString *)type {
  NSDictionary *map = @{@"heartRate" : @(QCMeasuringTypeHeartRate), @"spo2" : @(QCMeasuringTypeBloodOxygen),
                        @"bloodPressure" : @(QCMeasuringTypeBloodPressue), @"hrv" : @(QCMeasuringTypeHRV),
                        @"stress" : @(QCMeasuringTypeStress), @"temperature" : @(QCMeasuringTypeBodyTemperature)};
  NSNumber *n = map[type];
  return n ? (QCMeasuringType)n.integerValue : QCMeasuringTypeUnkown;
}

#pragma mark - Realtime heart rate

/// The ring stops streaming unless it hears Hold about every 20 s.
- (void)realtime:(BOOL)start result:(FlutterResult)result {
  [self.holdTimer invalidate];
  self.holdTimer = nil;
  if (!self.ready) return result([FlutterError errorWithCode:@"not_connected" message:@"ring is not connected" details:nil]);
  if (!start) {
    [QCSDKCmdCreator realTimeHeartRateWithCmd:QCBandRealTimeHeartRateCmdTypeEnd finished:nil];
    return result(nil);
  }
  [QCSDKCmdCreator realTimeHeartRateWithCmd:QCBandRealTimeHeartRateCmdTypeStart finished:nil];
  self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:kHoldRealtimeEvery repeats:YES block:^(NSTimer *t) {
    [QCSDKCmdCreator realTimeHeartRateWithCmd:QCBandRealTimeHeartRateCmdTypeHold finished:nil];
  }];
  result(nil);
}

#pragma mark - Bluetooth

- (CBCentralManager *)ensureCentral {
  if (!self.central) {
    self.central = [[CBCentralManager alloc] initWithDelegate:self
                                                        queue:dispatch_get_main_queue()
                                                      options:@{CBCentralManagerOptionShowPowerAlertKey : @YES}];
  }
  return self.central;
}

- (void)startScan:(NSTimeInterval)timeout result:(FlutterResult)result {
  CBCentralManager *c = [self ensureCentral];
  if (c.state != CBManagerStatePoweredOn) {
    // The first call creates the central; state settles a moment later.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (self.central.state == CBManagerStatePoweredOn) {
        [self startScan:timeout result:result];
      } else {
        result([FlutterError errorWithCode:@"bluetooth_off" message:@"Bluetooth is off or not authorised" details:nil]);
      }
    });
    return;
  }
  [self.discovered removeAllObjects];
  // Rings already connected to iOS do not advertise; list them first.
  NSArray *services = @[ [CBUUID UUIDWithString:QCBANDSDKSERVERUUID1], [CBUUID UUIDWithString:QCBANDSDKSERVERUUID2] ];
  for (CBPeripheral *p in [c retrieveConnectedPeripheralsWithServices:services]) {
    if (!p.name.length) continue;
    self.discovered[p.identifier.UUIDString] = p;
    [self emit:@{@"event" : @"scanResult", @"id" : p.identifier.UUIDString, @"name" : p.name, @"rssi" : @(-40)}];
  }
  [c scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @NO}];
  [self.scanTimer invalidate];
  self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(timeout, 1) repeats:NO block:^(NSTimer *t) {
    [self stopScan];
  }];
  result(nil);
}

- (void)stopScan {
  [self.scanTimer invalidate];
  self.scanTimer = nil;
  if (self.central.state == CBManagerStatePoweredOn) [self.central stopScan];
  [self emit:@{@"event" : @"scanStopped"}];
}

- (void)centralManager:(CBCentralManager *)central
    didDiscoverPeripheral:(CBPeripheral *)peripheral
        advertisementData:(NSDictionary<NSString *, id> *)adv
                     RSSI:(NSNumber *)RSSI {
  NSString *name = peripheral.name ?: adv[CBAdvertisementDataLocalNameKey];
  NSString *key = peripheral.identifier.UUIDString;
  if (!name.length || self.discovered[key]) return;
  self.discovered[key] = peripheral;
  NSMutableDictionary *e = [@{@"event" : @"scanResult", @"id" : key, @"name" : name, @"rssi" : RSSI} mutableCopy];
  NSString *mac = [QringSdkPlugin macFromAdvertisement:adv];
  if (mac) e[@"mac"] = mac;
  [self emit:e];
}

- (void)connect:(NSString *)identifier {
  if (!identifier.length) return;
  self.userDisconnected = NO;
  [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:kLastPeripheralKey];
  CBCentralManager *c = [self ensureCentral];
  if (c.state != CBManagerStatePoweredOn) {
    self.pendingConnectId = identifier;  // connect once the central powers on
    return;
  }
  CBPeripheral *p = self.discovered[identifier];
  if (!p) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
    if (uuid) p = [c retrievePeripheralsWithIdentifiers:@[ uuid ]].firstObject;
  }
  if (!p) {
    [self emit:@{@"event" : @"connection", @"state" : @"disconnected", @"id" : identifier}];
    return;
  }
  if (self.central.isScanning) [self stopScan];
  [[QCSDKManager shareInstance] removeAllPeripheral];
  self.peripheral = p;
  self.ready = NO;
  [self emitState:@"connecting"];
  if (p.state == CBPeripheralStateConnected) {
    [self centralManager:c didConnectPeripheral:p];
  } else {
    [c connectPeripheral:p options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey : @YES}];
  }
}

- (void)disconnectForget:(BOOL)forget {
  self.userDisconnected = YES;
  self.ready = NO;
  [self.holdTimer invalidate];
  [[QCSDKManager shareInstance] removeAllPeripheral];
  if (self.peripheral) [self.central cancelPeripheralConnection:self.peripheral];
  if (forget) [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLastPeripheralKey];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  BOOL on = central.state == CBManagerStatePoweredOn;
  [self emit:@{@"event" : @"bluetooth", @"on" : @(on)}];
  if (!on) return;
  NSString *target = self.pendingConnectId;
  if (!target && !self.userDisconnected && !self.ready && self.peripheral)
    target = self.peripheral.identifier.UUIDString;
  self.pendingConnectId = nil;
  if (target) [self connect:target];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
  [self emitState:@"connected"];
  QCSDKManager *sdk = [QCSDKManager shareInstance];
  [sdk removePeripheral:peripheral];
  [sdk addPeripheral:peripheral finished:^(BOOL success) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!success) {
        [self.central cancelPeripheralConnection:peripheral];
        return;
      }
      // Only now does QCBandSDK accept commands.
      self.ready = YES;
      [self emitState:@"ready"];
    });
  }];
}

- (void)centralManager:(CBCentralManager *)central
    didFailToConnectPeripheral:(CBPeripheral *)peripheral
                         error:(NSError *)error {
  self.ready = NO;
  [self emitState:@"disconnected"];
}

- (void)centralManager:(CBCentralManager *)central
    didDisconnectPeripheral:(CBPeripheral *)peripheral
                      error:(NSError *)error {
  self.ready = NO;
  [self.holdTimer invalidate];
  [[QCSDKManager shareInstance] removeAllPeripheral];
  [self emitState:@"disconnected"];
  if (!self.userDisconnected && central.state == CBManagerStatePoweredOn) {
    // Unexpected drop: CoreBluetooth retries for us until the ring is back in range.
    [central connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey : @YES}];
    [self emitState:@"connecting"];
  }
}

#pragma mark - Helpers

+ (double)kcal:(double)raw {
  // Ring firmwares report either kcal or small calories.
  return raw > 20000 ? raw / 1000.0 : raw;
}

+ (NSString *)hhmm:(NSInteger)minutes {
  return [NSString stringWithFormat:@"%02ld:%02ld", (long)((minutes / 60) % 24), (long)(minutes % 60)];
}

+ (double)midnightMs:(NSInteger)day {
  NSCalendar *cal = [NSCalendar currentCalendar];
  NSDate *today = [cal startOfDayForDate:[NSDate date]];
  return [cal dateByAddingUnit:NSCalendarUnitDay value:-day toDate:today options:0].timeIntervalSince1970 * 1000;
}

+ (double)msFromString:(NSString *)s {
  static NSDateFormatter *f;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  });
  NSDate *d = s.length ? [f dateFromString:s] : nil;
  return d ? d.timeIntervalSince1970 * 1000 : 0;
}

+ (id)sleepMap:(NSArray<QCSleepModel *> *)sleeps {
  NSMutableArray *segments = [NSMutableArray new];
  NSInteger deep = 0, light = 0, rem = 0, awake = 0;
  for (QCSleepModel *s in sleeps) {
    double start = [self msFromString:s.happenDate], end = [self msFromString:s.endTime];
    if (end <= start) continue;
    NSInteger minutes = (NSInteger)((end - start) / 60000);
    NSString *stage = @"unknown";
    switch (s.type) {
      case SLEEPTYPESOBER: stage = @"awake"; awake += minutes; break;
      case SLEEPTYPELIGHT: stage = @"light"; light += minutes; break;
      case SLEEPTYPEDEEP: stage = @"deep"; deep += minutes; break;
      case SLEEPTYPEREM: stage = @"rem"; rem += minutes; break;
      default: break;
    }
    [segments addObject:@{@"start" : @(start), @"end" : @(end), @"stage" : stage}];
  }
  if (!segments.count) return [NSNull null];
  [segments sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
    return [x[@"start"] compare:y[@"start"]];
  }];
  return @{@"start" : segments.firstObject[@"start"], @"end" : segments.lastObject[@"end"],
           @"deepMin" : @(deep), @"lightMin" : @(light), @"remMin" : @(rem), @"awakeMin" : @(awake),
           @"totalMin" : @(deep + light + rem), @"score" : @0, @"segments" : segments};
}

/// iOS never exposes MAC addresses; QC rings put theirs in the advertisement.
+ (NSString *)macFromAdvertisement:(NSDictionary *)adv {
  NSMutableArray<NSData *> *candidates = [NSMutableArray new];
  if ([adv[CBAdvertisementDataManufacturerDataKey] isKindOfClass:NSData.class])
    [candidates addObject:adv[CBAdvertisementDataManufacturerDataKey]];
  NSDictionary *svc = adv[CBAdvertisementDataServiceDataKey];
  if ([svc isKindOfClass:NSDictionary.class])
    for (id v in svc.allValues)
      if ([v isKindOfClass:NSData.class]) [candidates addObject:v];
  for (NSData *d in candidates) {
    const uint8_t *b = d.bytes;
    NSInteger off = d.length >= 10 ? 4 : d.length == 8 ? 2 : d.length == 6 ? 0 : -1;
    if (off < 0) continue;
    return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x", b[off], b[off + 1], b[off + 2],
                                      b[off + 3], b[off + 4], b[off + 5]];
  }
  return nil;
}

@end

#else

// QCBandSDK ships arm64 device code only. On the Simulator the plugin
// registers its channels but reports every command as unsupported, so the
// app can run on sample data.
@implementation QringSdkPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  QringSdkPlugin *plugin = [QringSdkPlugin new];
  FlutterMethodChannel *methods = [FlutterMethodChannel methodChannelWithName:@"qring_sdk/methods"
                                                              binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:plugin channel:methods];
  FlutterEventChannel *events = [FlutterEventChannel eventChannelWithName:@"qring_sdk/events"
                                                          binaryMessenger:[registrar messenger]];
  [events setStreamHandler:plugin];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"isConnected"]) return result(@NO);
  result([FlutterError errorWithCode:@"unsupported"
                             message:@"QCBandSDK has no iOS Simulator build; run on an iPhone."
                             details:nil]);
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  return nil;
}

@end

#endif
