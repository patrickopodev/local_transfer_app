import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_units.dart';

/// A reusable AdMob banner that loads a [BannerAd] on init and renders it
/// once available. Falls back to an empty placeholder while loading or if the
/// ad fails, so it never crashes the surrounding layout.
class AdBanner extends StatefulWidget {
  const AdBanner({
    super.key,
    required this.adUnitId,
    this.size = AdSize.mediumRectangle,
    this.align = Alignment.center,
  });

  final String adUnitId;
  final AdSize size;
  final Alignment align;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // MobileAds.initialize() is idempotent. Awaiting it here (in addition to
    // main()) guarantees we never call BannerAd.load() before init finishes,
    // which throws on some devices and would otherwise surface as a startup
    // crash. Any failure just leaves the empty placeholder.
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      return;
    }
    // In debug builds always use Google's test unit: production units may not
    // be serving yet and must not receive test traffic.
    final adUnitId = kDebugMode
        ? 'ca-app-pub-3940256099942544/6300978111'
        : widget.adUnitId;
    final ad = BannerAd(
      adUnitId: adUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (_, error) {
          final stale = _ad;
          _ad = null;
          try {
            stale?.dispose();
          } catch (_) {}
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (_) {
      final stale = _ad;
      _ad = null;
      try {
        stale?.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    final stale = _ad;
    _ad = null;
    try {
      stale?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size.width.toDouble();
    final height = widget.size.height.toDouble();
    if (AdConfig.screenshotMode) {
      return const SizedBox.shrink();
    }
    if (!_loaded || _ad == null) {
      return SizedBox(width: width, height: height);
    }
    return Align(
      alignment: widget.align,
      child: SizedBox(
        width: width,
        height: height,
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
