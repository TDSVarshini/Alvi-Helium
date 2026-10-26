#import <Flutter/Flutter.h>

/// Bridges QCBandSDK to Flutter. The app (this plugin) owns the
/// CBCentralManager; QCBandSDK only drives a peripheral it is handed.
@interface QringSdkPlugin : NSObject <FlutterPlugin, FlutterStreamHandler>
@end
