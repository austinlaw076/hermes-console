# Companions (Fase A) — mascotas locales

Galería **local** de mascotas cosméticas ("Companion") para Hermes Console.
Contrato público: [`docs/PETDEX_CONTRACT.md`](../../docs/PETDEX_CONTRACT.md).

## Estructura

Cada mascota vive en su propia carpeta:

```
assets/companions/<slug>/
├── pet.json          # metadatos + mapeo de estados (formato compatible Petdex)
└── spritesheet.webp  # rejilla 8×9, frames 192×208 (recomendado 1536×1872)
```

El formato de `pet.json` está definido en
[`docs/PETDEX_CONTRACT.md`](../../docs/PETDEX_CONTRACT.md).

## Reglas de licencia (OBLIGATORIO)

- Solo se incluyen aquí assets con **licencia propia o compatible** con la
  distribución en la APK. **NO** se incluye fan-art comunitario de Petdex
  (los pets de `petdex.dev` son de terceros y tienen sus propias licencias).
- Cada `pet.json` declara su campo `license`.
- El texto legal CC0-1.0 está en [`CC0-1.0.txt`](CC0-1.0.txt).
- La procedencia y los SHA-256 canónicos se fijan en
  [`../../ASSET_PROVENANCE.md`](../../ASSET_PROVENANCE.md).
- Presupuesto total de assets de Fase A: **≤ ~2 MB** (spritesheets `.webp`).

## Fuera de alcance (Fase A)

- Sin descarga remota desde `petdex.dev` (eso es Fase C).
- Sin contenido de usuario (UGC), sin moderación, sin economía/tienda.
