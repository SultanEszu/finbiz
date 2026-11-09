import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class FinBizLogo extends StatelessWidget {
  const FinBizLogo({
    super.key,
    this.showName = true,
    this.size = 28,
    this.nameColor,
  });

  final bool showName;
  final double size;
  final Color? nameColor;

  @override
  Widget build(BuildContext context) {
    final textColor = nameColor ?? AppColors.deepNavy;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size + 10,
          height: size + 10,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.deepNavy, AppColors.skyBlue],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepNavy.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'F',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.72,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          Text(
            'FinBiz',
            style: TextStyle(
              color: textColor,
              fontSize: size * 0.9,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );
  }
}
