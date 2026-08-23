/// Enlaces externos del módulo Companion (Fase B / US5).
///
/// Petdex es una **galería/fuente externa** de mascotas (no una tienda ni un
/// marketplace dentro de la app). El único uso permitido aquí es **abrir el
/// enlace en el navegador externo**: la app NO descarga nada, no hace peticiones
/// HTTP propias, no parsea respuestas y no instala por slug.
library;

/// URL canónica de Petdex.
///
/// VERIFICADA (2026-06-25): `https://petdex.dev` responde 200 y es el destino
/// canónico (el alias `https://petdex.crafter.run` redirige 308 a este host).
/// Detalle de la verificación del contrato en `docs/PETDEX_CONTRACT.md`.
const String kPetdexUrl = 'https://petdex.dev';

/// Indica si [kPetdexUrl] ya está verificada oficialmente. En `true` desde la
/// verificación del 2026-06-25 → la UI abre el enlace en el navegador externo.
///
/// Nota: esto habilita **únicamente** abrir Petdex en el navegador. NO habilita
/// descarga/instalación in-app: el contrato de assets de Petdex no expone la
/// geometría de animación ni autor/licencia que el motor de Fase A exige, por lo
/// que la instalación directa permanece fuera de alcance (ver doc del contrato).
const bool kPetdexUrlVerified = true;
