/// AdMob configuration.
///
/// Currently using Google's public TEST ad unit IDs so ads render in any build.
/// Replace [appId] and the unit IDs below with your real AdMob values before
/// publishing to Play Store — Google policy requires a registered app ID and
/// will reject builds that keep shipping test IDs in production.
abstract final class AdConfig {
  /// AdMob App ID, registered under your AdMob account.
  static const String appId = 'ca-app-pub-3940256099942544~3347511713';

  /// 300x250 in-content ad in the middle of the Home tab.
  static const String homeMediumRectangle =
      'ca-app-pub-3940256099942544/6300978111';

  /// 320x50 banner shown while a transfer is in progress.
  static const String transferBanner =
      'ca-app-pub-3940256099942544/6300978111';

  /// 320x50 banner pinned at the bottom of the Transfers tab.
  static const String transfersBanner =
      'ca-app-pub-3940256099942544/6300978111';
}
