import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/onboarding_service.dart';

/// 5-page animated onboarding shown on first launch only.
/// After completion → navigates to Welcome (create / join space).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  late final List<AnimationController> _pageAnimCtrls;

  static const _pages = [
    _PageData(
      imagePath: 'assets/images/onboarding_1.jpg',
      accentColor: Color(0xFFB388FF),
      title: 'Welcome to OurVerse',
      subtitle: 'A private space built just\nfor the two of you.',
      badge: null,
    ),
    _PageData(
      imagePath: 'assets/images/onboarding_2.jpg',
      accentColor: Color(0xFF64FFDA), // Keeping original accent colors, they look good on light too
      title: 'Daily Check-ins',
      subtitle: 'A new question every day.\nAnswer together, stay in each other\'s world.',
      badge: '🔥 Builds your streak',
    ),
    _PageData(
      imagePath: 'assets/images/onboarding_3.jpg',
      accentColor: Color(0xFFFFD54F),
      title: 'Play Together',
      subtitle: 'Mini games, word hunts, doodles —\nanything beats scrolling alone.',
      badge: '10+ games available',
    ),
    _PageData(
      imagePath: 'assets/images/onboarding_4.jpg',
      accentColor: Color(0xFFFF6E8A),
      title: 'Vibe & Watch Together',
      subtitle: 'Listen to music in sync.\nWatch YouTube at exactly the same time.',
      badge: '📺 Stream each other\'s screen',
    ),
    _PageData(
      imagePath: 'assets/images/onboarding_5.jpg',
      accentColor: Color(0xFFE8647A),
      title: 'Your Space, Your Rules',
      subtitle: 'No account. No strangers.\nJust you and your person.',
      badge: null,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageAnimCtrls = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _pageAnimCtrls[0].forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _pageAnimCtrls) c.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await OnboardingService.markOnboardingDone();
    if (mounted) context.go('/');
  }

  Future<void> _skip() async {
    HapticFeedback.lightImpact();
    await OnboardingService.markOnboardingDone();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // Dark status bar icons for light background
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar: dots + Skip ──────────────────────────────────
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(_pages.length, (i) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _currentPage ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _currentPage
                                  ? page.accentColor
                                  : onSurface.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      if (_currentPage < _pages.length - 1)
                        TextButton(
                          onPressed: _skip,
                          child: Text(
                            'Skip',
                            style: GoogleFonts.outfit(
                              color: onSurface.withValues(alpha: 0.5),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── PageView ──────────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentPage = i);
                    _pageAnimCtrls[i].reset();
                    _pageAnimCtrls[i].forward();
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    return _OnboardingPage(
                      data: _pages[index],
                      animCtrl: _pageAnimCtrls[index],
                    );
                  },
                ),
              ),

              // ── Bottom CTA ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 36),
                child: _currentPage < _pages.length - 1
                    ? _NextButton(
                        accentColor: page.accentColor,
                        onTap: () => _goToPage(_currentPage + 1),
                      )
                    : _GetStartedButtons(
                        accentColor: page.accentColor,
                        onFinish: _finish,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Page data model ──────────────────────────────────────────────────────────

class _PageData {
  final String imagePath;
  final Color accentColor;
  final String title;
  final String subtitle;
  final String? badge;

  const _PageData({
    required this.imagePath,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.badge,
  });
}

// ─── Single page content ──────────────────────────────────────────────────────

class _OnboardingPage extends StatelessWidget {
  final _PageData data;
  final AnimationController animCtrl;

  const _OnboardingPage({required this.data, required this.animCtrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    
    final fadeIn = CurvedAnimation(parent: animCtrl, curve: Curves.easeOut);
    final slideUp = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animCtrl, curve: Curves.easeOutCubic));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // ── Premium image with border ────────────────────────────
          FadeTransition(
            opacity: fadeIn,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: data.accentColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30.5),
                child: Image.asset(
                  data.imagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // ── Title ─────────────────────────────────────────────────────
          SlideTransition(
            position: slideUp,
            child: FadeTransition(
              opacity: fadeIn,
              child: Text(
                data.title,
                style: GoogleFonts.outfit(
                  color: onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Subtitle ──────────────────────────────────────────────────
          SlideTransition(
            position: slideUp,
            child: FadeTransition(
              opacity: fadeIn,
              child: Text(
                data.subtitle,
                style: GoogleFonts.outfit(
                  color: onSurface.withValues(alpha: 0.7),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // ── Optional badge ────────────────────────────────────────────
          if (data.badge != null) ...[
            const SizedBox(height: 24),
            FadeTransition(
              opacity: fadeIn,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: data.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: data.accentColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  data.badge!,
                  style: GoogleFonts.outfit(
                    color: data.accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

// ─── Next button ──────────────────────────────────────────────────────────────

class _NextButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _NextButton({required this.accentColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 56,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Next',
              style: GoogleFonts.outfit(
                color: Colors.white, // keep white text inside colored buttons
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Final page CTA ───────────────────────────────────────────────────────────

class _GetStartedButtons extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onFinish;

  const _GetStartedButtons({required this.accentColor, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    
    return Column(
      children: [
        GestureDetector(
          onTap: onFinish,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                'Get Started 🚀',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No account needed · Always free',
          style: GoogleFonts.outfit(
            color: onSurface.withValues(alpha: 0.4),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
