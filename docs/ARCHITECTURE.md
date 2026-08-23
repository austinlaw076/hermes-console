# Arquitectura — Hermes Mobile Client

## Diagrama de alto nivel

```
[Android App - Flutter]
         |
    [Tailscale / LAN / HTTPS]
         |
    [Hermes Gateway]  ← self-hosted
         |
    [Hermes Agent]
    ├── Memory
    ├── Cron
    ├── Skills
    └── MCP
```

## Capas de la app (objetivo)

```
lib/
├── main.dart
├── app/
│   └── app.dart              # MaterialApp, router, theme
├── features/
│   ├── chat/                 # Feature principal
│   │   ├── data/             # API calls a Gateway
│   │   ├── domain/           # Modelos, entidades
│   │   └── presentation/     # Screens, widgets
│   ├── settings/             # URL Gateway, API key
│   ├── auth/                 # Gestión API key
│   └── attachments/          # Adjuntos (fase futura)
├── core/
│   ├── api/                  # Cliente HTTP base
│   ├── storage/              # Secure storage wrapper
│   ├── error/                # Tipos de error
│   └── config/               # Constantes
└── shared/
    ├── widgets/              # Componentes reutilizables
    └── theme/                # Temas claro/oscuro
```

## Conexión con Hermes Gateway

- Protocolo: HTTP/HTTPS + SSE para streaming
- Autenticación: API key en header `Authorization: Bearer <key>`
- Endpoints conocidos (pendiente de verificar en audit):
  - `/chat` — chat principal
  - `/health` — estado del servidor
  - (completar tras audit de hermes-android)

## Almacenamiento seguro

- API key: `flutter_secure_storage` → Android Keystore
- URL del gateway: SharedPreferences (no es secreto)
- Historial: local DB (SQLite / Isar, a decidir)

## Conectividad

- **Tailscale**: preferida, sin exposición pública de puertos
- **LAN directa**: para homelab con red local
- **HTTPS con cert propio**: requiere trust anchor en la app
- **No requerido**: Google Play Services, FCM, ningún servicio cloud

## Decisiones de diseño pendientes

Ver `docs/DECISIONS.md`
