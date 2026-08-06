import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/subscription_service.dart';
import '../../../../shared/providers/subscription_providers.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen>
    with TickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  late AnimationController _floatCtrl;
  String? _selectedProductId = kProductYearly; // Default to best value
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final products = ref.watch(availableProductsProvider).valueOrNull ?? [];

    if (isPremium) {
      return _PremiumActiveScreen(onClose: () => Navigator.of(context).pop());
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D0D1A),
              Color(0xFF1A0A2E),
              Color(0xFF2D1040),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Close button ────────────────────────────────────────────
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // ── Animated header ──────────────────────────────────
                      _AnimatedHeroHeader(
                        shimmerCtrl: _shimmerCtrl,
                        floatCtrl: _floatCtrl,
                      ),
                      const SizedBox(height: 28),

                      // ── Feature list ─────────────────────────────────────
                      _FeatureList(),
                      const SizedBox(height: 32),

                      // ── Pricing cards ─────────────────────────────────────
                      if (products.isEmpty)
                        _LoadingProductsCard()
                      else
                        _PricingCards(
                          products: products,
                          selectedId: _selectedProductId,
                          onSelected: (id) =>
                              setState(() => _selectedProductId = id),
                        ),
                      const SizedBox(height: 24),

                      // ── CTA Button ────────────────────────────────────────
                      _CTAButton(
                        products: products,
                        selectedId: _selectedProductId,
                        isPurchasing: _isPurchasing,
                        onTap: _purchase,
                      ),
                      const SizedBox(height: 16),

                      // ── Restore Purchases ─────────────────────────────────
                      TextButton(
                        onPressed: _restorePurchases,
                        child: const Text(
                          'Restore Purchases',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      // ── Legal links ───────────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LegalLink(
                            label: 'Privacy Policy',
                            url:
                                'https://www.nexaaradhya.site/privacy/ourverse',
                          ),
                          const Text('  ·  ',
                              style: TextStyle(color: Colors.white24)),
                          _LegalLink(
                            label: 'Terms of Use',
                            url: 'https://www.nexaaradhya.site/terms/ourverse',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _purchase() async {
    final products = ref.read(availableProductsProvider).valueOrNull ?? [];
    final product = products.firstWhere(
      (p) => p.id == _selectedProductId,
      orElse: () => products.first,
    );

    setState(() => _isPurchasing = true);
    try {
      await SubscriptionService.instance.purchase(product);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${e.toString()}'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isPurchasing = true);
    await SubscriptionService.instance.restorePurchases();
    if (mounted) {
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchases restored!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    }
  }
}

// ─── Animated Hero Header ──────────────────────────────────────────────────────

class _AnimatedHeroHeader extends StatelessWidget {
  final AnimationController shimmerCtrl;
  final AnimationController floatCtrl;

  const _AnimatedHeroHeader({
    required this.shimmerCtrl,
    required this.floatCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([shimmerCtrl, floatCtrl]),
      builder: (_, __) {
        final floatOffset = sin(floatCtrl.value * pi) * 8;
        return Transform.translate(
          offset: Offset(0, floatOffset),
          child: Column(
            children: [
              // Crown with shimmer
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: const [
                    Color(0xFFFFD700),
                    Color(0xFFFFF3A0),
                    Color(0xFFFFD700),
                    Color(0xFFFFAA00),
                  ],
                  stops: [
                    0.0,
                    shimmerCtrl.value,
                    (shimmerCtrl.value + 0.3).clamp(0.0, 1.0),
                    1.0,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  '✨',
                  style: TextStyle(fontSize: 64),
                ),
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: const [
                    Color(0xFFFFD700),
                    Color(0xFFFF69B4),
                    Color(0xFFFFD700),
                  ],
                  stops: [
                    0.0,
                    shimmerCtrl.value,
                    1.0,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  'Ourverse Premium',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unlimited love. Zero limits.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Feature List ──────────────────────────────────────────────────────────────

class _FeatureList extends StatelessWidget {
  final List<_Feature> _features = const [
    _Feature(
      icon: '♾️',
      title: 'Unlimited Game Plays',
      subtitle: 'No daily limits on any game, ever.',
    ),
    _Feature(
      icon: '📺',
      title: 'Unlimited Streaming',
      subtitle: 'Stream together without any time cap.',
    ),
    _Feature(
      icon: '🚫',
      title: 'Completely Ad-Free',
      subtitle: 'No interstitials, banners, or popups.',
    ),
    _Feature(
      icon: '💕',
      title: 'Support Ourverse',
      subtitle: 'Help us build more features for you.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.2), width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: _features
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(f.icon, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              f.subtitle,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFFFFD700), size: 20),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Feature {
  final String icon, title, subtitle;
  const _Feature(
      {required this.icon, required this.title, required this.subtitle});
}

// ─── Pricing Cards ─────────────────────────────────────────────────────────────

class _PricingCards extends StatelessWidget {
  final List<ProductDetails> products;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _PricingCards({
    required this.products,
    required this.selectedId,
    required this.onSelected,
  });

  String _label(String id) {
    switch (id) {
      case kProductMonthly:
        return 'Monthly';
      case kProductYearly:
        return 'Yearly';
      case kProductLifetime:
        return 'Lifetime';
      default:
        return id;
    }
  }

  bool _isBestValue(String id) => id == kProductYearly;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: products.map((p) {
        final isSelected = selectedId == p.id;
        final isBest = _isBestValue(p.id);
        return GestureDetector(
          onTap: () => onSelected(p.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: isSelected
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFFD700)
                    : Colors.white.withValues(alpha: 0.15),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Radio
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFFFFD700)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.white38,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.black, size: 14)
                      : null,
                ),
                const SizedBox(width: 16),
                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _label(p.id),
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFFFFD700)
                                  : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          if (isBest) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BEST VALUE',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (p.id == kProductYearly)
                        const Text(
                          'Save 44% vs monthly',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      if (p.id == kProductLifetime)
                        const Text(
                          'Pay once, keep forever',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                // Price
                Text(
                  p.price,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFFD700) : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Loading Products Card ─────────────────────────────────────────────────────

class _LoadingProductsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFFD700), strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'Loading plans...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── CTA Button ────────────────────────────────────────────────────────────────

class _CTAButton extends StatelessWidget {
  final List<ProductDetails> products;
  final String? selectedId;
  final bool isPurchasing;
  final VoidCallback onTap;

  const _CTAButton({
    required this.products,
    required this.selectedId,
    required this.isPurchasing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String label = 'Get Ourverse Premium';
    if (products.isNotEmpty && selectedId != null) {
      final product = products.firstWhere(
        (p) => p.id == selectedId,
        orElse: () => products.first,
      );
      label = 'Get Premium · ${product.price}';
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isPurchasing || products.isEmpty ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
          child: isPurchasing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 2.5),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Legal Link ────────────────────────────────────────────────────────────────

class _LegalLink extends StatelessWidget {
  final String label, url;
  const _LegalLink({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white30,
        ),
      ),
    );
  }
}

// ─── Already Premium Screen ────────────────────────────────────────────────────

class _PremiumActiveScreen extends StatelessWidget {
  final VoidCallback onClose;
  const _PremiumActiveScreen({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D1A), Color(0xFF1A0A2E), Color(0xFF2D1040)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 72)),
                  const SizedBox(height: 20),
                  const Text(
                    'You\'re Premium! 💛',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Thank you for supporting Closer.\nEnjoy unlimited plays, streaming, and an ad-free experience!',
                    style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  FilledButton(
                    onPressed: onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      minimumSize: const Size(200, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                    child: const Text(
                      '🎉 Continue',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
