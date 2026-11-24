import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The custom stroke icon set from the design canvas (24-grid, 1.75 stroke).
class CcIcons {
  static const home = '<path d="M4 11l8-6.5 8 6.5v8.5a.5.5 0 0 1-.5.5H15v-5.5H9V20H4.5a.5.5 0 0 1-.5-.5z"/>';
  static const library = '<rect x="3" y="5" width="5" height="14" rx="1"/><rect x="9.5" y="5" width="5" height="14" rx="1"/><rect x="16" y="5" width="5" height="14" rx="1"/><path d="M2 12h20"/>';
  static const lab = '<rect x="4" y="3" width="16" height="18" rx="1.5"/><path d="M7.5 7h9M7.5 11h4"/><path d="M14 11c0 4 3 3 3 7"/><circle cx="14" cy="11" r="1"/>';
  static const diagram = '<path d="M3 4h18M3 20h18M9 4v3.5M9 11.5l-3-4M9 11.5V13M9 17v3"/><rect x="6.5" y="13" width="5" height="4"/><path d="M16 4v5.5M16 14.5V20"/><circle cx="16" cy="12" r="2.5"/>';
  static const quiz = '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8.5 8.5l1.5 1.5 2.5-3M8.5 15l1.5 1.5 2.5-3M15 9h1.5M15 15.5h1.5"/>';
  static const explode = '<rect x="9" y="9" width="6" height="6" rx="1"/><path d="M4 4l3 3M20 4l-3 3M4 20l3-3M20 20l-3-3M4 8V4h4M20 8V4h-4M4 16v4h4M20 16v4h-4"/>';
  static const assemble = '<rect x="8" y="8" width="8" height="8" rx="1"/><path d="M3 3l4 4M21 3l-4 4M3 21l4-4M21 21l-4-4"/>';
  static const tag = '<path d="M3.5 12.5l9-9h7.5V11l-9 9z"/><circle cx="15.5" cy="8.5" r="1.5"/>';
  static const audio = '<path d="M4 10v4h3l4 3V7l-4 3z"/><path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a7.5 7.5 0 0 1 0 11"/>';
  static const reset = '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/>';
  static const search = '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>';
  static const settings = '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>';
  static const warning = '<path d="M12 3.5L2.5 20h19z"/><path d="M12 10v4.5M12 17.2v.1"/>';
  static const back = '<path d="M9 6l6 6-6 6"/>';
  static const info = '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8v.1"/>';
  static const bolt = '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>';
  static const meter = '<rect x="6" y="3" width="12" height="18" rx="2"/><rect x="8.5" y="5.5" width="7" height="4" rx=".5"/><circle cx="12" cy="15" r="2.5"/><path d="M12 15l1.6-1.6"/>';
  static const book = '<path d="M4 5.5A1.5 1.5 0 0 1 5.5 4H11v16H5.5A1.5 1.5 0 0 1 4 18.5zM20 5.5A1.5 1.5 0 0 0 18.5 4H13v16h5.5a1.5 1.5 0 0 0 1.5-1.5z"/>';
  static const list = '<path d="M8 6h12M8 12h12M8 18h12"/><path d="M4 6h.01M4 12h.01M4 18h.01"/>';
}

class CcIcon extends StatelessWidget {
  final String paths;
  final double size;
  final Color? color;
  final double stroke;
  const CcIcon(this.paths, {super.key, this.size = 24, this.color, this.stroke = 1.75});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.white;
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" '
        'stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$paths</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}

/// App mark: a classic control current path (contact + coil between two lines).
class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 40});

  static const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
      '<rect x="0.5" y="0.5" width="39" height="39" rx="11" fill="#151C22" stroke="#26323C"/>'
      '<path d="M9 9h22M9 31h22" stroke="#5B6B78" stroke-width="2" stroke-linecap="round"/>'
      '<path d="M20 9v4.5M20 20.5l-4.5-6M20 20.5V22" stroke="#F5A400" stroke-width="2.2" stroke-linecap="round"/>'
      '<rect x="15.5" y="22" width="9" height="5.5" fill="none" stroke="#3FD5E8" stroke-width="2.2"/>'
      '<path d="M20 27.5V31" stroke="#3FD5E8" stroke-width="2.2" stroke-linecap="round"/></svg>';

  @override
  Widget build(BuildContext context) => SvgPicture.string(svg, width: size, height: size);
}
