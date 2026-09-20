/// AdMob configuration.
///
/// Production AdMob IDs (app + banner unit created 2026-09-20).
/// New ad units can take up to an hour to start serving real ads.
abstract final class AdConfig {
  /// AdMob App ID, registered under your AdMob account.
  static const String appId = 'ca-app-pub-3516223940521946~3416810830';

  /// 300x250 in-content ad in the middle of the Home tab.
  static const String homeMediumRectangle =
      'ca-app-pub-3516223940521946/6914956737';

  /// 320x50 banner shown while a transfer is in progress.
  static const String transferBanner =
      'ca-app-pub-3516223940521946/6914956737';

  /// 320x50 banner pinned at the bottom of the Transfers tab.
  static const String transfersBanner =
      'ca-app-pub-3516223940521946/6914956737';
}
