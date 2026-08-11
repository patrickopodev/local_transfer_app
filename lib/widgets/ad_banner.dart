import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (_, _) => _ad?.dispose(),
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (_) {
      // No ad SDK on the platform (or in tests) — keep the placeholder.
      _ad?.dispose();
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size.width.toDouble();
    final height = widget.size.height.toDouble();
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
