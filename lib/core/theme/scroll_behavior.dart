import 'package:flutter/material.dart';

/// Comportamiento de scroll de toda la app: física con **inercia** (coasting)
/// estilo iOS/Telegram. Un "flick" rápido del dedo sigue rodando y frena solo
/// cuando se le acaba el impulso, en vez del frenazo seco del scroll Material
/// por defecto (`ClampingScrollPhysics`). Da la sensación de "ruleta" que el
/// usuario pidió, y de paso unifica el tacto del scroll en listas, hojas y
/// desplazamientos horizontales (p. ej. tablas anchas).
///
/// Mantiene el resto del comportamiento Material (scrollbars, arrastre con
/// ratón/teclado, etc.) heredando de [MaterialScrollBehavior].
class MomentumScrollBehavior extends MaterialScrollBehavior {
  const MomentumScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
